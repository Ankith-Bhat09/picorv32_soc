`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// ASIC-friendly 8-bit SPI master for PicoRV32/native-bus integration
//
// Register map
//   0x00 CONTROL
//        bit 0 ENABLE
//        bit 1 CPHA
//        bit 2 CPOL
//        bit 3 LSB_FIRST
//
//   0x04 PRESCALE
//        [7:0] half-period divider.
//        0 -> toggle every clk
//        N -> toggle after N+1 clk cycles
//
//   0x08 TXDATA
//        write [7:0] to start an SPI transfer
//
//   0x0C RXDATA
//        read most recently completed received byte
//
//   0x10 CS
//        active-low chip-select vector
//        bit = 0 -> selected
//        bit = 1 -> inactive
//
//   0x14 STATUS
//        bit 0 BUSY
//        bit 1 DONE
//
// SPI:
//   * 8-bit transfers
//   * MSB-first or LSB-first
//   * CPOL = 0/1
//   * CPHA = 0/1
//   * Full duplex: MOSI transmitted while MISO is received
//
// ASIC rules:
//   * No FPGA primitives
//   * No generated internal clock
//   * All state runs from clk
//   * prescale creates a clock-enable event only
//
// SCL180 pad integration:
//   spi_mosi -> output pad
//   spi_miso <- input pad
//   spi_sclk -> output pad
//   spi_cs   -> output pads
// -----------------------------------------------------------------------------

module spi_master_asic #(
    parameter integer CS_LENGTH = 4
) (
    input  wire                    clk,
    input  wire                    resetn,

    input  wire                    iomem_valid,
    output reg                     iomem_ready,
    input  wire [3:0]              iomem_wstrb,
    input  wire [31:0]             iomem_addr,
    input  wire [31:0]             iomem_wdata,
    output reg  [31:0]             iomem_rdata,

    input  wire                    spi_miso,
    output wire                    spi_mosi,
    output wire                    spi_sclk,
    output wire [CS_LENGTH-1:0]    spi_cs
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;

    reg [1:0] state;

    reg       spi_enable;
    reg       cpha;
    reg       cpol;
    reg       lsb_first;

    reg [7:0] prescale;
    reg [7:0] prescale_cnt;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [7:0] rx_data;

    reg [3:0] bit_count;

    reg       sclk_reg;
    reg       mosi_reg;

    reg [CS_LENGTH-1:0] cs_reg;
    reg       done_reg;

    // A request is serviced only in the first cycle it is seen (ready still low),
    // so each access executes once and ready is a clean single-cycle pulse.
    wire bus_active = iomem_valid && !iomem_ready;
    wire bus_read   = bus_active && (iomem_wstrb == 4'b0000);
    wire bus_write  = bus_active && (iomem_wstrb != 4'b0000);

    wire [7:0] addr = iomem_addr[7:0];

    // A tick is a clock-enable, not a generated clock.
    wire spi_tick = (prescale_cnt == prescale);

    assign spi_mosi = mosi_reg;
    assign spi_sclk = sclk_reg;
    assign spi_cs   = cs_reg;

    // Select the bit being transmitted/received.
    function [2:0] bit_index;
        input [3:0] count;
        input       lsb;
        begin
            if (lsb)
                bit_index = count[2:0];
            else
                bit_index = 3'd7 - count[2:0];
        end
    endfunction

    // Received byte including the bit being sampled on THIS edge.
    // (CPHA=1 completes on the same edge that samples the last bit, so
    //  rx_shift alone is one bit short at that moment.)
    reg [7:0] rx_final;
    always @* begin
        rx_final = rx_shift;
        rx_final[bit_index(bit_count, lsb_first)] = spi_miso;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state        <= ST_IDLE;

            spi_enable   <= 1'b0;
            cpha         <= 1'b0;
            cpol         <= 1'b0;
            lsb_first    <= 1'b0;

            prescale     <= 8'd0;
            prescale_cnt <= 8'd0;

            tx_shift     <= 8'd0;
            rx_shift     <= 8'd0;
            rx_data      <= 8'd0;

            bit_count    <= 4'd0;

            sclk_reg     <= 1'b0;
            mosi_reg     <= 1'b0;

            cs_reg       <= {CS_LENGTH{1'b1}};
            done_reg     <= 1'b0;

            iomem_ready  <= 1'b0;
            iomem_rdata  <= 32'b0;
        end
        else begin
            // -------------------------------------------------------------
            // Native-bus response (registered, 1-cycle pulse per access)
            // -------------------------------------------------------------
            iomem_ready <= bus_active;

            // -------------------------------------------------------------
            // Register writes
            // -------------------------------------------------------------
            if (bus_write) begin
                case (addr)

                    8'h00: begin
                        // Control may be changed while idle only.
                        if (state == ST_IDLE) begin
                            spi_enable <= iomem_wdata[0];
                            cpha       <= iomem_wdata[1];
                            cpol       <= iomem_wdata[2];
                            lsb_first  <= iomem_wdata[3];

                            sclk_reg   <= iomem_wdata[2];
                        end
                    end

                    8'h04: begin
                        prescale <= iomem_wdata[7:0];
                    end

                    8'h08: begin
                        // Writing TXDATA starts an 8-bit transfer.
                        // Zero is a valid SPI data value.
                        if ((state == ST_IDLE) && spi_enable) begin
                            state        <= ST_RUN;
                            prescale_cnt <= 8'd0;
                            bit_count    <= 4'd0;
                            rx_shift     <= 8'd0;
                            done_reg     <= 1'b0;

                            tx_shift <= iomem_wdata[7:0];

                            if (!cpha) begin
                                // CPHA=0: first data bit is valid before
                                // the first active clock edge.
                                mosi_reg <= iomem_wdata[bit_index(4'd0, lsb_first)];
                            end
                            else begin
                                mosi_reg <= 1'b0;
                            end

                            // CS must already have been selected by
                            // software through the CS register.
                            sclk_reg <= cpol;
                        end
                    end

                    8'h10: begin
                        // Software controls chip-selects.
                        cs_reg <= iomem_wdata[CS_LENGTH-1:0];
                    end

                    default: begin
                    end
                endcase
            end

            // -------------------------------------------------------------
            // Register reads
            // -------------------------------------------------------------
            if (bus_read) begin
                case (addr)

                    8'h00: begin
                        iomem_rdata <= {
                            28'b0,
                            lsb_first,
                            cpol,
                            cpha,
                            spi_enable
                        };
                    end

                    8'h04: begin
                        iomem_rdata <= {24'b0, prescale};
                    end

                    8'h08: begin
                        iomem_rdata <= {24'b0, tx_shift};
                    end

                    8'h0C: begin
                        iomem_rdata <= {24'b0, rx_data};
                    end

                    8'h10: begin
                        iomem_rdata <= {{(32-CS_LENGTH){1'b0}}, cs_reg};
                    end

                    8'h14: begin
                        iomem_rdata <= {
                            30'b0,
                            done_reg,
                            (state == ST_RUN)
                        };
                    end

                    default: begin
                        iomem_rdata <= 32'b0;
                    end
                endcase
            end

            // -------------------------------------------------------------
            // SPI engine
            // -------------------------------------------------------------
            if (state == ST_RUN) begin

                if (spi_tick) begin
                    prescale_cnt <= 8'd0;

                    /*
                     * CPHA = 0
                     *
                     * At the active edge, sample MISO.
                     * At the inactive edge, prepare the next MOSI bit.
                     */
                    if (!cpha) begin

                        if (sclk_reg == cpol) begin
                            // Active edge.
                            rx_shift[bit_index(bit_count, lsb_first)]
                                <= spi_miso;

                            sclk_reg <= ~sclk_reg;
                        end
                        else begin
                            // Inactive edge.
                            sclk_reg <= ~sclk_reg;

                            if (bit_count == 4'd7) begin
                                // Transfer complete.
                                rx_data <= rx_shift;
                                state   <= ST_IDLE;
                                done_reg <= 1'b1;
                                sclk_reg <= cpol;
                            end
                            else begin
                                bit_count <= bit_count + 1'b1;

                                mosi_reg <= tx_shift[
                                    bit_index(bit_count + 1'b1, lsb_first)
                                ];
                            end
                        end
                    end

                    /*
                     * CPHA = 1
                     *
                     * First edge changes/launches data.
                     * Second edge samples MISO.
                     */
                    else begin

                        if (sclk_reg == cpol) begin
                            // First edge.
                            sclk_reg <= ~sclk_reg;

                            mosi_reg <= tx_shift[
                                bit_index(bit_count, lsb_first)
                            ];
                        end
                        else begin
                            // Second edge.
                            rx_shift[bit_index(bit_count, lsb_first)]
                                <= spi_miso;

                            sclk_reg <= ~sclk_reg;

                            if (bit_count == 4'd7) begin
                                rx_data <= rx_final;
                                state   <= ST_IDLE;
                                done_reg <= 1'b1;
                                sclk_reg <= cpol;
                            end
                            else begin
                                bit_count <= bit_count + 1'b1;
                            end
                        end
                    end
                end
                else begin
                    prescale_cnt <= prescale_cnt + 1'b1;
                end
            end
            else begin
                prescale_cnt <= 8'd0;
            end
        end
    end

endmodule

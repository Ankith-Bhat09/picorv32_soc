`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// ASIC-friendly GPIO peripheral for PicoRV32 native memory bus
//
// Register map
//   0x00 DIR   : 1 = output, 0 = input
//   0x04 OUT   : output data
//   0x08 SET   : write-1-to-set output bits
//   0x0C CLR   : write-1-to-clear output bits
//   0x10 IN    : sampled GPIO input pins
//
// Native bus:
//   iomem_wstrb == 4'b0000 -> read
//   nonzero wstrb            -> write
//
// The GPIO core contains NO technology-specific pad primitive.
// Connect gpio_in/gpio_out/gpio_oe to SCL180 pad cells at SoC top level.
// -----------------------------------------------------------------------------

module gpio_asic #(
    parameter integer GPIO_WIDTH = 16
) (
    input  wire                   clk,
    input  wire                   resetn,

    input  wire                   iomem_valid,
    output reg                    iomem_ready,
    input  wire [3:0]             iomem_wstrb,
    input  wire [31:0]            iomem_addr,
    input  wire [31:0]            iomem_wdata,
    output reg  [31:0]            iomem_rdata,

    input  wire [GPIO_WIDTH-1:0]   gpio_in,
    output wire [GPIO_WIDTH-1:0]   gpio_out,
    output wire [GPIO_WIDTH-1:0]   gpio_oe
);

    reg [GPIO_WIDTH-1:0] dir_reg;
    reg [GPIO_WIDTH-1:0] out_reg;

    // A request is serviced only in the first cycle it is seen (ready still low),
    // so each access executes once and ready is a clean single-cycle pulse.
    wire bus_active = iomem_valid && !iomem_ready;
    wire bus_read   = bus_active && (iomem_wstrb == 4'b0000);
    wire bus_write  = bus_active && (iomem_wstrb != 4'b0000);

    // Only the low 8 address bits are decoded; upper bits are decoded by the SoC.
    wire [7:0] addr = iomem_addr[7:0];

    assign gpio_out = out_reg;
    assign gpio_oe  = dir_reg;

    always @(posedge clk) begin
        if (!resetn) begin
            dir_reg      <= {GPIO_WIDTH{1'b0}};
            out_reg      <= {GPIO_WIDTH{1'b0}};
            iomem_ready  <= 1'b0;
            iomem_rdata  <= 32'b0;
        end
        else begin
            // One-wait-state native-bus response (registered ready, 1-cycle pulse).
            iomem_ready <= bus_active;

            // -------------------------------------------------------------
            // Writes
            // -------------------------------------------------------------
            if (bus_write) begin
                case (addr)
                    8'h00: begin
                        if (iomem_wstrb[0])
                            dir_reg[7:0] <= iomem_wdata[7:0];
                        if (iomem_wstrb[1] && GPIO_WIDTH > 8)
                            dir_reg[15:8] <= iomem_wdata[15:8];
                    end

                    8'h04: begin
                        if (iomem_wstrb[0])
                            out_reg[7:0] <= iomem_wdata[7:0];
                        if (iomem_wstrb[1] && GPIO_WIDTH > 8)
                            out_reg[15:8] <= iomem_wdata[15:8];
                    end

                    8'h08: begin
                        // SET: every written 1 sets the corresponding bit.
                        if (iomem_wstrb[0])
                            out_reg[7:0] <= out_reg[7:0] | iomem_wdata[7:0];
                        if (iomem_wstrb[1] && GPIO_WIDTH > 8)
                            out_reg[15:8] <= out_reg[15:8] | iomem_wdata[15:8];
                    end

                    8'h0C: begin
                        // CLR: every written 1 clears the corresponding bit.
                        if (iomem_wstrb[0])
                            out_reg[7:0] <= out_reg[7:0] & ~iomem_wdata[7:0];
                        if (iomem_wstrb[1] && GPIO_WIDTH > 8)
                            out_reg[15:8] <= out_reg[15:8] & ~iomem_wdata[15:8];
                    end

                    default: begin
                    end
                endcase
            end

            // -------------------------------------------------------------
            // Reads
            // -------------------------------------------------------------
            if (bus_read) begin
                case (addr)
                    8'h00: begin
                        iomem_rdata <= {{(32-GPIO_WIDTH){1'b0}}, dir_reg};
                    end

                    8'h04: begin
                        iomem_rdata <= {{(32-GPIO_WIDTH){1'b0}}, out_reg};
                    end

                    8'h08: begin
                        iomem_rdata <= 32'b0;
                    end

                    8'h0C: begin
                        iomem_rdata <= 32'b0;
                    end

                    8'h10: begin
                        iomem_rdata <= {{(32-GPIO_WIDTH){1'b0}}, gpio_in};
                    end

                    default: begin
                        iomem_rdata <= 32'b0;
                    end
                endcase
            end
        end
    end

endmodule

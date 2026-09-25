`timescale 1ns/1ps

// ================================================================
// Simple I2C Master
// PicoRV32 Native Memory Interface
//
// Register Map
//
// 0x00 : CONTROL
//        bit 0 = ENABLE
//
// 0x04 : CLOCK_DIV
//        I2C clock divider
//
// 0x08 : TXDATA
//        [7:0] transmit data
//
// 0x0C : RXDATA
//        [7:0] received data
//
// 0x10 : COMMAND
//        bit 0 = START
//        bit 1 = STOP
//        bit 2 = WRITE
//        bit 3 = READ
//        bit 4 = READ_NACK
//
//        READ_NACK = 0 -> send ACK after READ
//        READ_NACK = 1 -> send NACK after READ
//
// 0x14 : STATUS
//        bit 0 = BUSY
//        bit 1 = DONE
//        bit 2 = ACK_ERROR
//        bit 3 = RX_VALID
//
// I2C IO interface:
//
//        OE = 1 -> drive LOW
//        OE = 0 -> release line
//
//        DO = data output
//        DI = actual pad input
//
// Since I2C is open-drain, DO is always 0.
//
// ================================================================

module i2c_master_asic (

    // System
    input  wire        clk,
    input  wire        resetn,
    // PicoRV32 native memory interface
    input  wire        iomem_valid,
    output reg         iomem_ready,
    input  wire [3:0]  iomem_wstrb,
    input  wire [31:0] iomem_addr,
    input  wire [31:0] iomem_wdata,
    output reg  [31:0] iomem_rdata,
    // I2C SDA
    output wire        i2c_sda_oe,
    output wire        i2c_sda_do,
    input  wire        i2c_sda_di,
    // I2C SCL
    output wire        i2c_scl_oe,
    output wire        i2c_scl_do,
    input  wire        i2c_scl_di
);
    // FSM STATES
    localparam [3:0]

        ST_IDLE       = 4'd0,

        ST_START_1    = 4'd1,
        ST_START_2    = 4'd2,

        ST_WRITE_LOW  = 4'd3,
        ST_WRITE_HIGH = 4'd4,

        ST_ACK_LOW    = 4'd5,
        ST_ACK_HIGH   = 4'd6,

        ST_READ_LOW   = 4'd7,
        ST_READ_HIGH  = 4'd8,

        ST_READ_ACK_L = 4'd9,
        ST_READ_ACK_H = 4'd10,

        ST_STOP_1     = 4'd11,
        ST_STOP_2     = 4'd12;

    reg [3:0] state;

    // CONTROL REGISTERS   
    reg        enable;
    reg [7:0]  clock_div;
    reg [7:0]  clock_cnt;

    // DATA REGISTERS
    reg [7:0] tx_data;
    reg [7:0] rx_data;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [3:0] bit_count;

    // COMMAND REGISTERS
   reg cmd_start;
    reg cmd_stop;
    reg cmd_write;
    reg cmd_read;
    reg cmd_read_nack;
    
    // STATUS REGISTERS
    reg done;
    reg ack_error;
    reg rx_valid;


     
    // I2C OPEN-DRAIN OUTPUT ENABLE
    //
    // OE = 1 -> pull line LOW
    // OE = 0 -> release line
     

    reg sda_oe_reg;
    reg scl_oe_reg;


     
    // I2C OUTPUT CONNECTIONS
    //
    // I2C DO is always zero because I2C is open-drain.
     

    assign i2c_sda_oe = sda_oe_reg;
    assign i2c_sda_do = 1'b0;

    assign i2c_scl_oe = scl_oe_reg;
    assign i2c_scl_do = 1'b0;


     
    // PICO RV32 BUS
     

    wire bus_active;

    assign bus_active =
        iomem_valid && !iomem_ready;


    wire bus_write;

    assign bus_write =
        bus_active &&
        (iomem_wstrb != 4'b0000);


    wire bus_read;

    assign bus_read =
        bus_active &&
        (iomem_wstrb == 4'b0000);


    wire [7:0] addr;

    assign addr = iomem_addr[7:0];


     
    // I2C CLOCK TICK
     

    wire i2c_tick;

    assign i2c_tick =
        (clock_cnt >= clock_div);


     
    // SEQUENTIAL LOGIC
     

    always @(posedge clk) begin


         
        // RESET
         

        if (!resetn) begin

            state <= ST_IDLE;

            enable <= 1'b0;

            clock_div <= 8'd49;
            clock_cnt <= 8'd0;

            tx_data <= 8'd0;
            rx_data <= 8'd0;

            tx_shift <= 8'd0;
            rx_shift <= 8'd0;

            bit_count <= 4'd0;

            cmd_start <= 1'b0;
            cmd_stop <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read <= 1'b0;
            cmd_read_nack <= 1'b0;

            done <= 1'b0;
            ack_error <= 1'b0;
            rx_valid <= 1'b0;

            sda_oe_reg <= 1'b0;
            scl_oe_reg <= 1'b0;

            iomem_ready <= 1'b0;
            iomem_rdata <= 32'd0;

        end


         
        // NORMAL OPERATION
         

        else begin


             
            // PICO RV32 BUS RESPONSE
             

            iomem_ready <= bus_active;


             
            // REGISTER WRITE
             

            if (bus_write) begin

                case (addr)


                     
                    // CONTROL
                     

                    8'h00: begin

                        if (state == ST_IDLE)
                            enable <= iomem_wdata[0];

                    end


                     
                    // CLOCK DIVIDER
                     

                    8'h04: begin

                        clock_div <= iomem_wdata[7:0];

                    end


                     
                    // TX DATA
                     

                    8'h08: begin

                        tx_data <= iomem_wdata[7:0];

                    end


                     
                    // COMMAND
                     

                    8'h10: begin

                        if ((state == ST_IDLE) && enable) begin

                            cmd_start <= iomem_wdata[0];
                            cmd_stop <= iomem_wdata[1];
                            cmd_write <= iomem_wdata[2];
                            cmd_read <= iomem_wdata[3];
                            cmd_read_nack <= iomem_wdata[4];

                            done <= 1'b0;
                            ack_error <= 1'b0;
                            rx_valid <= 1'b0;

                            tx_shift <= tx_data;
                            rx_shift <= 8'd0;

                            bit_count <= 4'd0;

                            clock_cnt <= 8'd0;


                             
                            // START
                             

                            if (iomem_wdata[0]) begin

                                state <= ST_START_1;

                                // Release SDA
                                sda_oe_reg <= 1'b0;

                                // Release SCL
                                scl_oe_reg <= 1'b0;

                            end


                             
                            // STOP
                             

                            else if (iomem_wdata[1]) begin

                                state <= ST_STOP_1;

                                // SDA LOW
                                sda_oe_reg <= 1'b1;

                                // SCL LOW
                                scl_oe_reg <= 1'b1;

                            end


                             
                            // WRITE
                             

                            else if (iomem_wdata[2]) begin

                                state <= ST_WRITE_LOW;

                                // SCL LOW
                                scl_oe_reg <= 1'b1;

                                // Send first bit (MSB)
                                if (tx_data[7])
                                    sda_oe_reg <= 1'b0;
                                else
                                    sda_oe_reg <= 1'b1;

                            end


                             
                            // READ
                             

                            else if (iomem_wdata[3]) begin

                                state <= ST_READ_LOW;

                                // Release SDA
                                sda_oe_reg <= 1'b0;

                                // SCL LOW
                                scl_oe_reg <= 1'b1;

                            end

                        end

                    end


                    default: begin
                    end

                endcase

            end


             
            // REGISTER READ
             

            if (bus_read) begin

                case (addr)


                     
                    // CONTROL
                     

                    8'h00: begin

                        iomem_rdata <= {
                            31'd0,
                            enable
                        };

                    end


                     
                    // CLOCK DIVIDER
                     

                    8'h04: begin

                        iomem_rdata <= {
                            24'd0,
                            clock_div
                        };

                    end


                     
                    // TX DATA
                     

                    8'h08: begin

                        iomem_rdata <= {
                            24'd0,
                            tx_data
                        };

                    end


                     
                    // RX DATA
                     

                    8'h0C: begin

                        iomem_rdata <= {
                            24'd0,
                            rx_data
                        };

                    end


                     
                    // STATUS
                     

                    8'h14: begin

                        iomem_rdata <= {
                            28'd0,
                            rx_valid,
                            ack_error,
                            done,
                            (state != ST_IDLE)
                        };

                    end


                    default: begin

                        iomem_rdata <= 32'd0;

                    end

                endcase

            end


             
            // I2C ENGINE
             

            if (state != ST_IDLE) begin


                 
                // CLOCK DIVIDER
                 

                if (i2c_tick) begin

                    clock_cnt <= 8'd0;


                    case (state)


                         
                        // START STEP 1
                         

                        ST_START_1: begin

                            // Bus released

                            sda_oe_reg <= 1'b0;
                            scl_oe_reg <= 1'b0;

                            state <= ST_START_2;

                        end


                         
                        // START STEP 2
                         

                        ST_START_2: begin

                            // SDA LOW while SCL HIGH
                            // = START condition

                            sda_oe_reg <= 1'b1;

                            scl_oe_reg <= 1'b1;


                            // -----------------------------------------
                            // START + WRITE
                            // -----------------------------------------

                            if (cmd_write) begin

                                bit_count <= 4'd0;

                                tx_shift <= tx_data;

                                if (tx_data[7])
                                    sda_oe_reg <= 1'b0;
                                else
                                    sda_oe_reg <= 1'b1;

                                state <= ST_WRITE_LOW;

                            end


                            // -----------------------------------------
                            // START + READ
                            // -----------------------------------------

                            else if (cmd_read) begin

                                bit_count <= 4'd0;

                                rx_shift <= 8'd0;

                                sda_oe_reg <= 1'b0;

                                state <= ST_READ_LOW;

                            end
                            // START only
                            else begin

                                state <= ST_IDLE;

                                done <= 1'b1;

                            end

                        end


                         
                        // WRITE LOW
                         

                        ST_WRITE_LOW: begin

                            // Put data on SDA

                            if (tx_shift[7 - bit_count[2:0]])
                                sda_oe_reg <= 1'b0;
                            else
                                sda_oe_reg <= 1'b1;


                            // SCL HIGH

                            scl_oe_reg <= 1'b0;

                            state <= ST_WRITE_HIGH;

                        end


                         
                        // WRITE HIGH
                         

                        ST_WRITE_HIGH: begin

                            // SCL LOW

                            scl_oe_reg <= 1'b1;


                            if (bit_count == 4'd7) begin

                                // 8 bits transmitted

                                bit_count <= 4'd0;

                                // Release SDA for ACK

                                sda_oe_reg <= 1'b0;

                                state <= ST_ACK_LOW;

                            end

                            else begin

                                bit_count <= bit_count + 1'b1;

                                state <= ST_WRITE_LOW;

                            end

                        end


                         
                        // ACK LOW
                         

                        ST_ACK_LOW: begin

                            // Release SDA

                            sda_oe_reg <= 1'b0;

                            // SCL HIGH

                            scl_oe_reg <= 1'b0;

                            state <= ST_ACK_HIGH;

                        end


                         
                        // ACK HIGH
                         

                        ST_ACK_HIGH: begin

                            // ACK = SDA LOW
                            // NACK = SDA HIGH

                            if (i2c_sda_di)
                                ack_error <= 1'b1;
                            else
                                ack_error <= 1'b0;


                            // SCL LOW

                            scl_oe_reg <= 1'b1;


                            state <= ST_IDLE;

                            done <= 1'b1;

                        end


                         
                        // READ LOW
                         

                        ST_READ_LOW: begin

                            // Release SDA

                            sda_oe_reg <= 1'b0;

                            // SCL HIGH

                            scl_oe_reg <= 1'b0;

                            state <= ST_READ_HIGH;

                        end


                         
                        // READ HIGH
                         

                        ST_READ_HIGH: begin
                            // Sample SDA
                            rx_shift[7 - bit_count[2:0]]
                                <= i2c_sda_di;
                            // SCL LOW
                            scl_oe_reg <= 1'b1;
                            if (bit_count == 4'd7) begin
                                bit_count <= 4'd0;
                                // ACK
                                if (!cmd_read_nack)
                                    sda_oe_reg <= 1'b1;
                                // NACK
                                else
                                    sda_oe_reg <= 1'b0;
                                state <= ST_READ_ACK_L;
                            end
                            else begin
                                bit_count <= bit_count + 1'b1;
                                state <= ST_READ_LOW;
                            end
                        end

                        // READ ACK/NACK LOW
                        ST_READ_ACK_L: begin
                            // Raise SCL
                            scl_oe_reg <= 1'b0;
                            state <= ST_READ_ACK_H;
                        end

                        // READ ACK/NACK HIGH
                        ST_READ_ACK_H: begin
                            // Finish cycle
                            scl_oe_reg <= 1'b1;
                            sda_oe_reg <= 1'b0;
                            // Save received data
                            rx_data <= rx_shift;
                            rx_valid <= 1'b1;
                            state <= ST_IDLE;
                            done <= 1'b1;
                        end

                        // STOP STEP 1
                        ST_STOP_1: begin
                            // SDA LOW
                            sda_oe_reg <= 1'b1;
                            // SCL HIGH
                            scl_oe_reg <= 1'b0;
                            state <= ST_STOP_2;
                        end

                        // STOP STEP 2
                        ST_STOP_2: begin
                            // Release SDA while SCL HIGH
                            // SDA LOW -> HIGH
                            // = STOP condition
                            sda_oe_reg <= 1'b0;
                            state <= ST_IDLE;
                            done <= 1'b1;
                        end

                        // DEFAULT
                        default: begin
                            state <= ST_IDLE;
                            sda_oe_reg <= 1'b0;
                            scl_oe_reg <= 1'b0;
                        end
                    endcase
                end

                // CLOCK COUNTER
                else begin
                    clock_cnt <= clock_cnt + 1'b1;
                end
            end

            // IDLE
            else begin
                clock_cnt <= 8'd0;
            end
        end
    end
endmodule

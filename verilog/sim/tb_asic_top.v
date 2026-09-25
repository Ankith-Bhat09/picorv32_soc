`timescale 1ns/1ps

module tb_asic_top;

    reg clk;
    reg resetn;

    // ============================================================
    // GPIO
    // ============================================================
    reg  [15:0] gpio_in;
    wire [15:0] gpio_out;
    wire [15:0] gpio_oe;

    // ============================================================
    // SPI
    // ============================================================
    wire spi_clk;
    wire spi_mosi;
    wire spi_miso;
    wire spi_cs;

    // ============================================================
    // UART
    // ============================================================
    wire ser_tx;

    // ============================================================
    // I2C
    // Open-drain bidirectional lines
    // ============================================================
    wire i2c_sda;
    wire i2c_scl;

    // External I2C pull-up resistors
    // In simulation, released lines should become HIGH.
    pullup(i2c_sda);
    pullup(i2c_scl);

    // ============================================================
    // DUT
    // ============================================================
    asic_top #(
        .MEM_WORDS(4096),              // 16 KB SRAM
        .PROGADDR_RESET(32'h00000000)
    ) dut (
        .clk      (clk),
        .resetn   (resetn),

        // GPIO
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_oe  (gpio_oe),

        // SPI
        .spi_sclk (spi_clk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .spi_cs   (spi_cs),

        // UART
        .ser_tx   (ser_tx),

        // I2C
        .i2c_sda  (i2c_sda),
        .i2c_scl  (i2c_scl)
    );

    // ============================================================
    // Clock: 100 MHz
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Reset
    // ============================================================
    initial begin
        resetn   = 1'b0;
        gpio_in  = 16'h0000;

        #200;
        resetn = 1'b1;
    end

    // ============================================================
    // I2C Slave Model
    //
    // For now this is only a basic bus monitor.
    // It observes START, STOP, address/data and ACK.
    // ============================================================

    reg [7:0] i2c_slave_data;
    reg [7:0] i2c_slave_addr;

    initial begin
        i2c_slave_addr = 8'h50;
        i2c_slave_data = 8'hA5;
    end

    // ------------------------------------------------------------
    // Detect START condition
    // SDA: HIGH -> LOW while SCL is HIGH
    // ------------------------------------------------------------
    always @(negedge i2c_sda) begin
        if (i2c_scl === 1'b1) begin
            $display("[%0t] I2C START detected", $time);
        end
    end

    // ------------------------------------------------------------
    // Detect STOP condition
    // SDA: LOW -> HIGH while SCL is HIGH
    // ------------------------------------------------------------
    always @(posedge i2c_sda) begin
        if (i2c_scl === 1'b1) begin
            $display("[%0t] I2C STOP detected", $time);
        end
    end

    // ------------------------------------------------------------
    // Monitor I2C data on SCL rising edge
    // ------------------------------------------------------------
    reg [7:0] i2c_rx_shift;
    reg [3:0] i2c_bit_count;

    initial begin
        i2c_rx_shift = 8'h00;
        i2c_bit_count = 4'd0;
    end

    always @(posedge i2c_scl) begin

        if (i2c_bit_count < 8) begin

            i2c_rx_shift = {
                i2c_rx_shift[6:0],
                i2c_sda
            };

            i2c_bit_count = i2c_bit_count + 1'b1;

            if (i2c_bit_count == 7) begin
                $display("[%0t] I2C Byte received = %02h",
                         $time,
                         {i2c_rx_shift[6:0], i2c_sda});
            end

        end
        else begin
            i2c_bit_count = 4'd0;
        end

    end

    // ============================================================
    // Simulation
    // ============================================================
    initial begin

        $dumpfile("asic_top.vcd");
        $dumpvars(0, tb_asic_top);

        #5_000_000;

        $display("========================================");
        $display(" Simulation timeout");
        $display("========================================");

        $finish;
    end

    // ============================================================
    // Observe CPU program counter
    // ============================================================
    always @(posedge clk) begin
        if (resetn) begin
            $display("[%0t] PC=%08x",
                     $time,
                     dut.soc.cpu.reg_pc);
        end
    end

endmodule

// Irp 
// top module for asic implementation of picosoc

`ifdef PICOSOC_V
`error "asic_top.v must be read before picosoc.v!"
`endif


module asic_top (
	input clk,
    input resetn,

	output ser_tx,
	input ser_rx,    
    
    //spi interface
    input  wire     spi_miso,
    output wire     spi_mosi,
    output wire     spi_sclk,
    output wire     spi_cs,

    //gpio interface
    input  wire [15:0]   gpio_in,
    output wire [15:0]   gpio_out,
    output wire [15:0]   gpio_oe,
    
    output wire i2c_sda_oe,
    output wire i2c_sda_do,
    input wire i2c_sda_di,

    output wire i2c_scl_oe,
    output wire i2c_scl_do,
    input wire i2c_scl_di,
	
    output flash_csb,
	output flash_clk,
    output wire flash_io0_oe,
    output wire flash_io0_do,
    input wire flash_io0_di,

    output wire flash_io1_oe,
    output wire flash_io1_do,
    input wire flash_io1_di,

    output wire flash_io2_oe,
    output wire flash_io2_do,
    input wire flash_io2_di,

    output wire flash_io3_oe,
    output wire flash_io3_do,
    input wire flash_io3_di
);
	parameter integer MEM_WORDS = 256;

	wire        iomem_valid;
	wire        iomem_ready;
	wire [3:0]  iomem_wstrb;
	wire [31:0] iomem_addr;
	wire [31:0] iomem_wdata;
	wire [31:0] iomem_rdata;

// Internal wires for GPIO and Spi I2C

    wire gpio_sel;
    wire spi_sel;
    wire i2c_sel;
    
    wire gpio_ready;
    wire spi_ready;
    wire i2c_ready;

    wire [31:0] gpio_rdata;
    wire [31:0] spi_rdata;
    wire [31:0] i2c_rdata;


                                                                    //           (31-24)_(23-16)_(15-8)_(7-0)
    assign gpio_sel = iomem_valid && (iomem_addr[31:12] == 20'h03000);//       0x 03      00      00     00

    assign spi_sel = iomem_valid && (iomem_addr[31:12] == 20'h03001);//        0x 03      00      10     00

    assign i2c_sel = iomem_valid && (iomem_addr[31:12] == 20'h03002);//        0x 03      00      20     00

    assign iomem_ready = gpio_sel ? gpio_ready : spi_sel ? spi_ready : i2c_sel ? i2c_ready : 1'b0;

    assign iomem_rdata = gpio_sel ? gpio_rdata : spi_sel ? spi_rdata : i2c_sel ? i2c_rdata : 32'b0;

// Soc implementation and inititation 
	picosoc #(
		.BARREL_SHIFTER(0),
		.ENABLE_MUL(0),
		.ENABLE_DIV(0),
		.ENABLE_FAST_MUL(1),
		.MEM_WORDS(MEM_WORDS)
	) soc (
		.clk          (clk      ),
		.resetn       (resetn   ),

		.ser_tx       (ser_tx   ),
		.ser_rx       (ser_rx   ),

		.flash_csb    (flash_csb),
		.flash_clk    (flash_clk),

		.flash_io0_oe (flash_io0_oe),
		.flash_io1_oe (flash_io1_oe),
		.flash_io2_oe (flash_io2_oe),
		.flash_io3_oe (flash_io3_oe),

		.flash_io0_do (flash_io0_do),
		.flash_io1_do (flash_io1_do),
		.flash_io2_do (flash_io2_do),
		.flash_io3_do (flash_io3_do),

		.flash_io0_di (flash_io0_di),
		.flash_io1_di (flash_io1_di),
		.flash_io2_di (flash_io2_di),
		.flash_io3_di (flash_io3_di),

		.irq_5        (1'b0        ),
		.irq_6        (1'b0        ),
		.irq_7        (1'b0        ),

		.iomem_valid  (iomem_valid ),
		.iomem_ready  (iomem_ready ),
		.iomem_wstrb  (iomem_wstrb ),
		.iomem_addr   (iomem_addr  ),
		.iomem_wdata  (iomem_wdata ),
		.iomem_rdata  (iomem_rdata )
	);


// Gpio and Spi implementation and initiation
    gpio_asic #(
        .GPIO_WIDTH(16)
    ) u_gpio (
        .clk          (clk),
        .resetn       (resetn),

        .iomem_valid  (gpio_sel),
        .iomem_ready  (gpio_ready),
        .iomem_wstrb  (iomem_wstrb),
        .iomem_addr   (iomem_addr),
        .iomem_wdata  (iomem_wdata),
        .iomem_rdata  (gpio_rdata),

        .gpio_in      (gpio_in),
        .gpio_out     (gpio_out),
        .gpio_oe      (gpio_oe)
    );


    spi_master_asic #(
        .CS_LENGTH(1)
    ) u_spi (
        .clk          (clk),
        .resetn       (resetn),

        .iomem_valid  (spi_sel),
        .iomem_ready  (spi_ready),
        .iomem_wstrb  (iomem_wstrb),
        .iomem_addr   (iomem_addr),
        .iomem_wdata  (iomem_wdata),
        .iomem_rdata  (spi_rdata),

        .spi_miso     (spi_miso),
        .spi_mosi     (spi_mosi),
        .spi_sclk     (spi_sclk),
        .spi_cs       (spi_cs)
    );

    i2c_master_asic u_i2c (
    .clk          (clk),
    .resetn       (resetn),

    .iomem_valid  (i2c_sel),
    .iomem_ready  (i2c_ready),
    .iomem_wstrb  (iomem_wstrb),
    .iomem_addr   (iomem_addr),
    .iomem_wdata  (iomem_wdata),
    .iomem_rdata  (i2c_rdata),

    .i2c_sda_oe   (i2c_sda_oe),
    .i2c_sda_do   (i2c_sda_do),
    .i2c_sda_di   (i2c_sda_di),

    .i2c_scl_oe   (i2c_scl_oe),
    .i2c_scl_do   (i2c_scl_do),
    .i2c_scl_di   (i2c_scl_di)
);
endmodule

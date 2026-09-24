/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

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
    
	output flash_csb,
	output flash_clk,
	inout  flash_io0,
	inout  flash_io1,
	inout  flash_io2,
	inout  flash_io3
);
	parameter integer MEM_WORDS = 256;

// External pins to out of asic_top
    wire flash_io0_oe;
    wire flash_io0_do;
    wire flash_io0_di;

    wire flash_io1_oe;
    wire flash_io1_do;
    wire flash_io1_di;

    wire flash_io2_oe;
    wire flash_io2_do;
    wire flash_io2_di;

    wire flash_io3_oe;
    wire flash_io3_do;
    wire flash_io3_di;


	wire        iomem_valid;
	wire        iomem_ready;
	wire [3:0]  iomem_wstrb;
	wire [31:0] iomem_addr;
	wire [31:0] iomem_wdata;
	wire [31:0] iomem_rdata;

// Internal wires for GPIO and Spi

    wire gpio_sel;
    wire spi_sel;
    wire        gpio_ready;
    wire [31:0] gpio_rdata;
    wire        spi_ready;
    wire [31:0] spi_rdata;
                                                                    //           (31-24)_(23-16)_(15-8)_(7-0)
    assign gpio_sel = iomem_valid && (iomem_addr[31:12] == 20'h03000);//       0x 03      00      00     00

    assign spi_sel = iomem_valid && (iomem_addr[31:12] == 20'h03001);//        0x 03      00      10     00

    assign iomem_ready = gpio_sel ? gpio_ready : spi_sel  ? spi_ready  : 1'b0;

    assign iomem_rdata = gpio_sel ? gpio_rdata : spi_sel  ? spi_rdata  : 32'b0;


    assign flash_io0 = flash_io0_oe ? flash_io0_do : 1'bz;
    assign flash_io1 = flash_io1_oe ? flash_io1_do : 1'bz;
    assign flash_io2 = flash_io2_oe ? flash_io2_do : 1'bz;
    assign flash_io3 = flash_io3_oe ? flash_io3_do : 1'bz;

    assign flash_io0_di = flash_io0;
    assign flash_io1_di = flash_io1;
    assign flash_io2_di = flash_io2;
    assign flash_io3_di = flash_io3;

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
endmodule

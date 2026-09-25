#include <stdint.h>

/* ============================================================
 * GPIO
 * ============================================================*/
#define GPIO_BASE 0x03000000u

#define GPIO_DIR (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_OUT (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_SET (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_CLR (*(volatile uint32_t *)(GPIO_BASE + 0x0C))
#define GPIO_IN  (*(volatile uint32_t *)(GPIO_BASE + 0x10))

/* ============================================================
 * SPI
 * ============================================================*/
#define SPI_BASE 0x03001000u

#define SPI_CONTROL  (*(volatile uint32_t *)(SPI_BASE + 0x00))
#define SPI_SCALER   (*(volatile uint32_t *)(SPI_BASE + 0x04))
#define SPI_TXDATA   (*(volatile uint32_t *)(SPI_BASE + 0x08))
#define SPI_RXDATA   (*(volatile uint32_t *)(SPI_BASE + 0x0C))
#define SPI_CS       (*(volatile uint32_t *)(SPI_BASE + 0x10))
#define SPI_STATUS   (*(volatile uint32_t *)(SPI_BASE + 0x14))

/* ============================================================
 * UART
 * ============================================================*/
#define UART_BASE 0x02000000u
#define UART_DATA (*(volatile uint32_t *)(UART_BASE + 0x08))

/* ============================================================
 * I2C
 * ============================================================*/
#define I2C_BASE 0x03002000u

#define I2C_CONTROL   (*(volatile uint32_t *)(I2C_BASE + 0x00))
#define I2C_CLOCK_DIV (*(volatile uint32_t *)(I2C_BASE + 0x04))
#define I2C_TXDATA    (*(volatile uint32_t *)(I2C_BASE + 0x08))
#define I2C_RXDATA    (*(volatile uint32_t *)(I2C_BASE + 0x0C))
#define I2C_COMMAND   (*(volatile uint32_t *)(I2C_BASE + 0x10))
#define I2C_STATUS    (*(volatile uint32_t *)(I2C_BASE + 0x14))

/* ============================================================
 * UART API
 * ============================================================*/
void uart_putc(char c)
{
    UART_DATA = (uint32_t)c;
}

void uart_write(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* ============================================================
 * I2C API
 * ============================================================*/

/* Enable I2C */
void i2c_enable(void)
{
    I2C_CONTROL = 0x01;
}

/* Disable I2C */
void i2c_disable(void)
{
    I2C_CONTROL = 0x00;
}

/* Set I2C clock divider */
void i2c_clock_div(uint8_t div)
{
    I2C_CLOCK_DIV = div;
}
static inline void i2c_wait(void)
{
    while (I2C_STATUS & 0x01);
}
static inline uint8_t i2c_ack_error(void)
{
    return (I2C_STATUS >> 2) & 0x01;
}
void i2c_start(void)
{
    I2C_COMMAND = 0x01;       // START
    i2c_wait();
}

void i2c_stop(void)
{
    I2C_COMMAND = 0x02;       // STOP
    i2c_wait();
}
uint8_t i2c_write_byte(uint8_t data)
{
    I2C_TXDATA = data;
    I2C_COMMAND = 0x04;        // WRITE
    i2c_wait();
    return !i2c_ack_error();
}
uint8_t i2c_read_byte_ack(void)
{
    I2C_COMMAND = 0x08;        // READ
    i2c_wait();
    return I2C_RXDATA & 0xFF;
}
uint8_t i2c_read_byte_nack(void)
{
    I2C_COMMAND = 0x18;        // READ + READ_NACK
    i2c_wait();
    return I2C_RXDATA & 0xFF;
}
uint8_t i2c_write(uint8_t addr, uint8_t reg, uint8_t data)
{
    i2c_start();
    if (!i2c_write_byte((addr << 1) | 0)) {
        i2c_stop();
        return 0;
    }
    if (!i2c_write_byte(reg)) {
        i2c_stop();
        return 0;
    }
    if (!i2c_write_byte(data)) {
        i2c_stop();
        return 0;
    }
    i2c_stop();
    return 1;
}
uint8_t i2c_read(uint8_t addr, uint8_t reg)
{
    uint8_t data;
    /* Write register address */
    i2c_start();
    if (!i2c_write_byte((addr << 1) | 0)) {
        i2c_stop();
        return 0;
    }
    if (!i2c_write_byte(reg)) {
        i2c_stop();
        return 0;
    }

    /* Repeated START */
    i2c_start();
    if (!i2c_write_byte((addr << 1) | 1)) {
        i2c_stop();
        return 0;
    }
    /* Last byte -> NACK */
    data = i2c_read_byte_nack();
    i2c_stop();
    return data;
}
/* ============================================================
 * GPIO API
 * ============================================================*/
void gpio_dir(uint32_t dir)
{
    GPIO_DIR = dir;
}

void gpio_out(uint32_t value)
{
    GPIO_OUT = value;
}

uint32_t gpio_read(void)
{
    return GPIO_IN;
}

void gpio_set(uint32_t mask)
{
    GPIO_SET = mask;
}

void gpio_clear(uint32_t mask)
{
    GPIO_CLR = mask;
}

/* ============================================================
 * SPI API
 * ============================================================*/

static inline void spi_wait(void)
{
    while (SPI_STATUS & 0x01);
}

/* Mode = 0,1,2,3 */
void spi_mode(uint8_t mode)
{
    uint32_t ctrl = 0x01;      // ENABLE

    if (mode & 1) ctrl |= (1 << 1);   // CPHA
    if (mode & 2) ctrl |= (1 << 2);   // CPOL

    SPI_CONTROL = ctrl;
}

/* Clock divider */
void spi_scaler(uint8_t div)
{
    SPI_SCALER = div;
}

/* Select chip (0..3) */
void spi_select(uint8_t cs)
{
    SPI_CS = ~(1u << cs);
}

void spi_deselect(void)
{
    SPI_CS = 0xFFFFFFFF;
}

/* Transfer one byte */
uint8_t spi_transfer(uint8_t tx)
{
    SPI_TXDATA = tx;
    spi_wait();
    return SPI_RXDATA & 0xFF;
}

/* Send one byte */
void spi_send(uint8_t data)
{
    spi_transfer(data);
}

/* Read one byte */
uint8_t spi_read(void)
{
    return spi_transfer(0xFF);
}

/* Send a C string */
void spi_write(const char *text)
{
    while (*text)
        spi_send((uint8_t)*text++);
}

int main(void)
{
    gpio_dir(0x00FF);

    uart_write("Boot OK\r\n");

    gpio_out(0x55);

    /* SPI */
    spi_mode(0);
    spi_scaler(4);

    spi_select(0);
    spi_write("Ankith");
    spi_deselect();

    uart_write("SPI OK\r\n");

    /* ========================================================
     * I2C
     * ========================================================*/

    i2c_enable();

    /* Set I2C clock divider */
    i2c_clock_div(4);

    uart_write("I2C START\r\n");

    /* Example:
     * I2C slave address = 0x50
     * Register          = 0x10
     * Data              = 0xA5
     */
    if (i2c_write(0x50, 0x10, 0xA5))
    {
        uart_write("I2C WRITE OK\r\n");
    }
    else
    {
        uart_write("I2C WRITE ERROR\r\n");
    }

    /* Example read */
    uint8_t data;

    data = i2c_read(0x50, 0x10);

    uart_write("I2C READ DONE\r\n");

    while (1);
}

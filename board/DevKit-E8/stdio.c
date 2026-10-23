#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include "Driver_USART.h"
#include "pinconf.h"
#include "soc.h"

extern ARM_DRIVER_USART Driver_USART4;
static int ready;

/* DK-E8 PRG USB is switched to UART4 by SW4. The pack config uses
 * P12_1/P12_2 function 2 for UART4 RX/TX (AUGD0023 v1.2 p.7). */
int board_stdio_init(void) {
    if (ready) return 0;
    if (pinconf_set(PORT_12, PIN_1, PINMUX_ALTERNATE_FUNCTION_2, PADCTRL_READ_ENABLE) ||
        pinconf_set(PORT_12, PIN_2, PINMUX_ALTERNATE_FUNCTION_2, PADCTRL_OUTPUT_DRIVE_STRENGTH_4MA))
        return -1;
    if (Driver_USART4.Initialize(NULL) != ARM_DRIVER_OK ||
        Driver_USART4.PowerControl(ARM_POWER_FULL) != ARM_DRIVER_OK ||
        Driver_USART4.Control(ARM_USART_MODE_ASYNCHRONOUS | ARM_USART_DATA_BITS_8 |
                              ARM_USART_PARITY_NONE | ARM_USART_STOP_BITS_1 |
                              ARM_USART_FLOW_CONTROL_NONE, 115200) != ARM_DRIVER_OK ||
        Driver_USART4.Control(ARM_USART_CONTROL_TX, 1) != ARM_DRIVER_OK ||
        Driver_USART4.Control(ARM_USART_CONTROL_RX, 1) != ARM_DRIVER_OK)
        return -1;
    ready = 1;
    return 0;
}

int _write(int fd, char *data, int length) {
    if (fd != 1 && fd != 2) { errno = EBADF; return -1; }
    if (board_stdio_init()) { errno = EIO; return -1; }
    return Driver_USART4.Send(data, (uint32_t)length) == ARM_DRIVER_OK ? length : -1;
}

int _read(int fd, char *data, int length) {
    if (fd != 0) { errno = EBADF; return -1; }
    if (length <= 0) return 0;
    if (board_stdio_init()) { errno = EIO; return -1; }
    return Driver_USART4.Receive(data, 1) == ARM_DRIVER_OK ? 1 : -1;
}

int _isatty(int fd) { return fd >= 0 && fd <= 2; }
int _fstat(int fd, struct stat *st) { (void)fd; st->st_mode = S_IFCHR; return 0; }
int _close(int fd) { (void)fd; errno = EBADF; return -1; }
int _lseek(int fd, int offset, int whence) { (void)fd; (void)offset; (void)whence; return 0; }
int _getpid(void) { return 1; }
int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }
__attribute__((noreturn)) void _exit(int status) { (void)status; for (;;) { __asm__ volatile("wfi"); } }

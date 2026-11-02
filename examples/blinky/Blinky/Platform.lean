module
prelude
public import Blinky.HalError
namespace Blinky.Platform
public section
-- Board identities and the native ISR adapter, never CMSIS API substitutes.
@[extern "lean_blinky_gpio_driver"] private opaque gpioDriverRaw (_unit : Unit) : USize
def gpioDriver : USize := gpioDriverRaw ()
@[extern "lean_blinky_pin"] opaque pin (selector : UInt32) : UInt32
@[extern "lean_blinky_button_irq"] private opaque buttonIRQRaw (_unit : Unit) : UInt32
def buttonIRQ : UInt32 := buttonIRQRaw ()
@[extern "lean_blinky_button_port"] private opaque buttonPortRaw (_unit : Unit) : USize
def buttonPort : USize := buttonPortRaw ()
@[extern "lean_blinky_button_pin"] private opaque buttonPinRaw (_unit : Unit) : UInt32
def buttonPin : UInt32 := buttonPinRaw ()
@[extern "lean_blinky_callback"] private opaque callbackRaw (_unit : Unit) : USize
def callback : USize := callbackRaw ()
end
end Blinky.Platform

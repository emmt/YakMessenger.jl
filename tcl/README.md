# Tcl/Tk implementation of Yak messaging system

`Yak` is *yet another kind* of messaging system.

## Usage

Connect to server:

``` tcl
set conn [Yak::connect ?$host? $port]
```


### High level interface

Make server execute a command or evaluate an expression:

``` tcl
set answer [Yak::send $conn $expr]
```


### Low level interface

Send a message:

``` tcl
Yak::send_message $conn $type $mesg
```

Receive a message and retrieve its type and content:

``` tcl
set result [Yak::recv_message $conn]
set type [lindex $result 0]
set mesg [lindex $result 1]
```

# Yorick implementation of Yak messaging system

This directory contains a [Yorick](https://github.com/LLNL/yorick) implementation of the Yak
message protocol. File [`yak.i`](./yak.i) implements a simple Yak server executing Yorick
commands, and the functions for Yorick clients.

## Server side

A server is started by `yak_start`, stopped by `yak_shutdown`.


## Client side

To connect a client:

    sock = yak_connect(port);

with `port` the port number where the server is listening. The connection is automatically
closed when `sock` is no longer used. The connection may be explicitly closed by calling
`close, sock`.

To evaluate an expression:

    result = yak_send(sock, expr);
    yak_send, sock, expr;

Example:

    val = yak_send(sock, "varname");     // retrieve the value of a global variable
    yak_send, sock, "fma";               // call a sub-routine with no arguments
    yak_send, sock, "pli, random(4,5)";  // call a sub-routine with arguments
    val = yak_send(sock, "sqrt(x) + y"); // evaluate expression

Restrictions:

- the expression to evaluate must only involve global symbols;
- the expression to evaluate must consist in a single statement;
- the result is returned as a string.


## Installation

Copy file [`yak.i`](./yak.i) in directory `Y_SITE/i0` and file
[`yak-start.i`](./yak-start.i) in directory `Y_SITE/i-start` where `$Y_SITE` is Yorick's
platform independent *site directory*.

If you have [`EasyYorick`](https://github.com/emmt/EasyYorick) installed, then just do:

``` sh
ypkg update ypkg  # update EasyYorick database and code
ypkg install yak  # install Yak for Yorick
```


## Message format

The protocol is simple and based on messages of the form (using shell syntax):

    "${type}:${size}\n${mesg}\n"

where `${type}` is a single ASCII character specifying the type of the message: `X` for an
eXpression to be evaluated, `E` for an Error, `R` for a Result, `${size}` is the length of
the message content (in bytes, not accounting for the final newline), `\n` is a newline
character (ASCII 0x0a) and `${mesg}` is the message content. The header part of the message
`"${type}:${size}\n"` is textual; the remaining part may be binary or textual.

A server only responds to messages of type `X`. Other messages are just printed.

A client sends messages of type `X` and receives answers of type `R` (in case of success) or
`E` (in case of error).

# YakMessenger [![Build Status](https://github.com/emmt/YakMessenger.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/emmt/YakMessenger.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/emmt/YakMessenger.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/emmt/YakMessenger.jl)

`YakMessenger` is *yet another kind* of messaging system to exchange textual messages
between a server and its connected clients.

## Contents

In the [`src`](./src) directory, there is a Julia implementation of the messaging system
with methods for Julia clients.

In the [`c`](./c) directory, there is a C implementation of the messaging system with
methods for clients and a small demonstration program.

In the [`tcl`](./tcl) directory, there is a Tcl/Tk implementation of the messaging
system and functions for Yorick clients.

In the [`yorick`](./yorick) directory, there is a Yorick implementation of the messaging
system, with a simple Yorick command server and functions for Yorick clients.

## Julia usage for clients

First create a connection to the server:

``` julia
import YakMessenger
conn = YakMessenger.connect([host,] port)
```

or (at your convenience):

``` julia

using YakMessenger
conn = YakConnection([host,] port)
```

with `port` the port number (an integer) where the server is listening and `host` the
address of the machine running the server. Argument `host` is optional, if omitted the
server is assumed to run on the same machine as the client.

To send a command to the server (and receive an answer), simply do:

    answer = conn(command)

where `command` is a string whose interpretation depends on the server.

The connection is automatically closed when `conn` is garbage collected but may be
explicitly closed by `close(conn)`.

At a lower level, a Yak connection can be used by a server and a client to send and
receive individual messages:

``` julia
YakMessenger.send_message(conn, id, mesg)
(id, mesg) = YakMessenger.recv_message(mesg)
```

where `id` is the message type (see *Message format* below) and `mesg` is the message
content. These methods are the building-blocks for implementing Yak clients, servers, and
handling of new message types.


## The Yak messaging system

### Message format

The protocol is simple and based on messages of the form (using a shell-like syntax):

``` sh
"${id}:${len}\n${mesg}\n"
```

where `${id}` is a single ASCII character specifying the type of the message (more on this
below), `${len}` is the human readable length of the message content (in bytes, not
accounting for the final newline), `\n` is a newline character (ASCII 0x0a) and `${mesg}`
is the message content.

The format of a message is intended to be printable (if `mesg` is printable) and easy to
parse. When receiving a message, the size of the message can be inferred by reading the
header `${id}:${len}\n` of the message is only a few number of bytes. If a received
message appears to be corrupted or malformed, the connection shall be closed by the
receiver. The receiver can start by reading the 4 first bytes (the minimal header size),
then reads the remaining header part byte-by-byte (until the first newline), and finally
reads the `len + 1` bytes of the `${mesg}\n` part. In that way it is less likely for the
receiver to be blocked when reading a connection is a blocking operation.

### Message types

The following message types are implemented (more may be added later):

- Clients send messages of type `X` to have an e**X**pression evaluated by the server and
  receive a single message in response: either a type-`R` message with the **R**esult, or
  a type-`E` message with an **E**rror message.

- Servers only respond to messages of type `X` as explained above. Message of type `E`
  are printed as errors. Other messages are just printed or ignored.

### Implementation notes

In Yorick, when a callback is called with no pending data to receive, it means that
connection has been closed by peer. In a callback, commands like `pause` are not allowed.
Calls to `sockrecv` are blocking.

It takes a few tens of microseconds for a Julia client to send a simple command to a
Yorick Yak server and receive the answer.

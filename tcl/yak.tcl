#
# `YakMessenger` is *yet another kind* of messaging system.
#
# Connect to server:
#
#     set conn [Yak::connect ?$host? $port]
#
# Low level functions:
#
#     Yak::send_message $conn $type $mesg; # send a message
#     set result [Yak::recv_message $conn]; # receive a message
#     set type [lindex $result 0]; # retrieve the type of the message
#     set mesg [lindex $result 1]; # retrieve the content of the message
#
# Make server execute a command or evaluate an expression:
#
#     set answer [Yak::send $conn $expr]
#
namespace eval ::Yak {
    #+
    #     Yak::connect ?$host? $port -> $conn
    #
    # Connect to server on given `$host` and `$port`. Localhost is assumed if `$host` is
    # not specified.
    #
    # To send a command to the server (and receive an answer), simply do:
    #
    #     set answer [Yak::send $command]
    #
    # where `$command` is a string whose interpretation depends on the server.
    #
    # See also `Yak::send_message` and `Yak::recv_message`.
    #
    #-
    proc connect {args} {
        if {[llength $args] == 1} {
            set host "localhost"
            set port [lindex $args 0]
        } elseif {[llength $args] == 2} {
            set host [lindex $args 0]
            set port [lindex $args 1]
        } else {
            error "syntax: connect ?host? port"
        }
        set conn [socket $host $port]
        fconfigure $conn -blocking true -encoding binary -translation binary
        return $conn
    }

    proc send {conn cmd} {
        send_message $conn X $cmd
        set result [recv_message $conn]
        set type   [lindex $result 0]
        set answer [lindex $result 1]
        if {[string equal $type R]} {
            return $answer
        } elseif {[string equal $type E]} {
            error $answer
        } else {
            #close $conn
            error "Unexpected message type received as answer"
        }
    }

    #+
    #     Yak::send_message $conn $type $mesg
    #
    # Send a message to the connected peer on `$conn`. Argument `$type` is a character to
    # specify the message type. Argument `$mesg` is the message content.
    #
    # See also `Yak::recv_message` and `Yak::connect`.
    #
    #-
    proc send_message {conn type mesg} {
        if {![string is ascii $type] || [string length $type] != 1} {
            error "Message type must be a single ASCII character"
        }
        set size [string bytelength $mesg]
        puts $conn "${type}:${size}"; # newline automatically added
        puts $conn $mesg; # newline automatically added
        flush $conn
    }

    #+
    #     Yak::recv_message $conn -> {$type $mesg}
    #
    # Receive a message from the connected peer on `$conn`. The result is a list of 2
    # elements: `$type` is the message type, `$mesg` is the message content.
    #
    # See also `Yak::send_message` and `Yak::connect`.
    #
    #-
    proc recv_message {conn} {
        # Read the 4 first bytes (the minimal possible size of a message header) of the
        # message header.
        set buf [read $conn 4]
        if {[string bytelength $buf] != 4
            || ![string is ascii $buf]
            || [binary scan $buf "aaaa" type colon size byte] != 4
            || ![string equal $colon ":"]
            || ![string is digit $size]} {
            close $conn
            error "Invalid message header"
        }
        # Read the rest of the message header one byte at a time until the newline
        # separator is encountered.
        while {![string equal $byte "\n"]} {
            if {[string is ascii $byte] && [string is digit $byte]} {
                append size $byte
            } else {
                close $conn
                if {[string bytelength $byte] < 1} {
                    error "Truncated message header"
                } else {
                    error "Invalid non-digit/newline character in message header"
                }
            }
            set byte [read $conn 1]
        }
        # Read the message content and the final newline.
        set mesg [read $conn $size]
        set c [read $conn 1]
        if {! [string equal $c "\n"]} {
            close $conn
            error "Missing final newline character in message"
        }
        return [list $type $mesg]
    }
}; # namespace

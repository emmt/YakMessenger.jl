"""

`YakMessenger` is *yet another kind* of messenging system.

"""
module YakMessenger

export YakConnection

using Sockets

struct YakError
    mesg::String
end

function Base.showerror(io::IO, err::YakError)
    print(io, "YakError: ")
    print(io, err.mesg)
end

mutable struct YakConnection{T<:IO}
    io::T
    YakConnection(io::IO) where {IO} = finalizer(close, new{IO}(io))
end

# Extend base functions.
Base.isopen(conn::YakConnection) = isopen(conn.io)
function Base.close(conn::YakConnection)
    if isopen(conn)
        close(conn.io)
    end
    return nothing
end
#Base.write(conn::YakConnection, args...) = write(conn.io, args...)
#Base.read(conn::YakConnection, args...) = read(conn.io, args...)
#Base.read!(conn::YakConnection, args...) = read!(conn.io, args...)

"""
    import YakMessenger
    conn = YakMessenger.connect([host,] port)

    using YakMessenger
    conn = YakConnection([host,] port)

Connect to server on given `host` and `port`. Localhost is assumed if `host` is not
specified.

To send a command to the server (and receive an answer), simply do:

    answer = conn(command)

where `command` is a string whose interpretation depends on the server.

The connection is automatically closed when `conn` is garbage collected but may be
explicitly closed by `close(conn)`.

"""
YakConnection(port::Integer) = connect(port)
YakConnection(host, port::Integer) = connect(host, port)

connect(port::Integer) = YakConnection(Sockets.connect(port))
connect(host, port::Integer) = YakConnection(Sockets.connect(host, port))

function (conn::YakConnection)(mesg::AbstractString)
    send_message(conn, 'X', mesg)
    type, answer = recv_message(conn)
    type == 'E' && throw(YakError(answer))
    return answer
end

"""
    YakMessenger.send_message(conn, type, mesg)

Send a message to the connected peer on `conn`. Argument `type` is a character
to specify the message type. Argument `mesg` is the message content.

Also see [`YakMessenger.recv_message`](@ref).

"""
send_message(conn::YakConnection, id::Char, mesg::AbstractString) =
    send_message(codeunit(mesg), conn, id, mesg)

function send_message(::DataType, conn::YakConnection, id::Char, mesg::AbstractString)
    mesg = String(mesg)
    codeunit(mesg) === UInt8 || error("cannot convert message to code unit `UInt8`")
    return send_message(UInt8, conn, id, mesg)
end

function send_message(::Type{UInt8}, conn::YakConnection, id::Char, mesg::AbstractString)
    codeunit(mesg) === UInt8 || throw(ArgumentError(
        "expecting code unit `UInt8`, got $(codeunit(mesg))"))
    len = ncodeunits(mesg) # number of bytes of the message
    ndigits = 1
    m = 10
    while len ≥ m
        ndigits += 1
        m *= 10
    end
    buffer = Array{UInt8}(undef, 4 + ndigits + len)
    i = firstindex(buffer) - 1
    buffer[i += 1] = id
    buffer[i += 1] = ':'
    r = len
    for j in 1:ndigits
        m = div(m, 10)
        q, r = divrem(r, m)
        buffer[i += 1] = '0' + q
    end
    buffer[i += 1] = '\n'
    for j in 1:len
        buffer[i += 1] = codeunit(mesg, j)
    end
    buffer[i += 1] = '\n'
    @assert i == length(buffer)
    write(conn.io, buffer) # FIXME close connection on error?
    return nothing
end

"""
    YakMessenger.recv_message(conn) -> (type, mesg)

Receive a message from the connected peer on `conn`. The result is a 2-tuple: `type` is
the message type, `mesg` is the message content.

Also see [`YakMessenger.send_message`](@ref).

"""
function recv_message(conn::YakConnection)

    # Read the message header. The minimal header size if 4 bytes. The remaining bytes are
    # read one by one.
    newline = UInt8('\n')
    buffer = Array{UInt8}(undef, 4)
    read!(conn.io, buffer)
    mesg_type = Char(buffer[1]) # message type
    if buffer[2] != UInt8(':')
        close(conn)
        throw(malformed_message(':', byte))
    end
    local byte
    mesg_size = 0
    index = 2
    while true
        index += 1
        byte = index ≤ length(buffer) ? buffer[index] : read(conn.io, UInt8)
        if byte == UInt8('\n') && index ≥ 4
            break
        elseif UInt8('0') ≤ byte ≤ UInt8('9')
            digit = Int(byte) - Int('0')
            mesg_size = digit + 10*mesg_size
        else
            close(conn)
            throw(malformed_message("a digit", byte))
        end
    end

    # Read the remainingg part of the message, that is its content.
    read!(conn.io, resize!(buffer, mesg_size + 1)) # +1 for the final newline
    byte = buffer[end]
    if byte != UInt8('\n')
        close(conn)
        throw(malformed_message('\n', byte))
    end
    mesg = String(resize!(buffer, mesg_size))
    return mesg_type, mesg
end

hex(b::Unsigned) = string(b, base=16)
hex(c::Char) = hex(Integer(c))

@noinline malformed_message(c::Char, b::UInt8) =
    YakError("malformed message, expecting a '$c' (ASCII 0x$(hex(c))), got 0x$(hex(b))")

@noinline malformed_message(s::AbstractString, b::UInt8) =
    YakError("malformed message, expecting $s, got 0x$(hex(b))")

end # module

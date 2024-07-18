"""

`YakMessenger` is *yet another kind* of messaging system.

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

See also [`YakMessenger.send_message`](@ref) and [`YakMessenger.recv_message`](@ref).

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

See also [`YakMessenger.recv_message`](@ref).

"""
send_message(conn::YakConnection, type::Char, mesg::AbstractString) =
    send_message(conn, type, codeunits(mesg))

function send_message(::Type{UInt8}, conn::YakConnection, type::Char,
                      mesg::AbstractVector{T}) where {T}
    isconcretetype(T) || throw(ArgumentError(
        "message content must have elements of concrete type, got `$T`"))
    nbytes = sizeof(T)*length(mesg) # number of bytes of the message
    ndigits, m = 1, 10
    while m ≤ nbytes
        ndigits += 1
        m *= 10
    end
    header = Array{UInt8}(undef, 3 + ndigits)
    i = firstindex(header) - 1
    header[i += 1] = type
    header[i += 1] = ':'
    rest = nbytes
    for j in 1:ndigits
        m = div(m, 10)
        digit, rest = divrem(rest, m)
        header[i += 1] = '0' + digit
    end
    header[i += 1] = '\n'
    @assert i == length(header)
    write(conn.io, header) # FIXME close connection on error?
    write(conn.io, mesg) # FIXME close connection on error?
    write(conn.io, UInt8('\n')) # FIXME close connection on error?
    return nothing
end

"""
    YakMessenger.recv_message([T = String,] conn) -> (type, mesg::T)

Receive a message from the connected peer on `conn`. The result is a 2-tuple: `type` is
the message type, `mesg` is the message content. Optional argument `T` is the type of
`mesg`: either `String` (the default) or `Vector{UInt8}`.

See also [`YakMessenger.send_message`](@ref).

"""
recv_message(conn::YakConnection) = recv_message(String, conn)

function recv_message(::Type{Vector{UInt8}}, conn::YakConnection)
    type, mesg = recv_message(Vector{UInt8}, conn)
    return type, String(mesg)
end

function recv_message(::Type{Vector{UInt8}}, conn::YakConnection)

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
    mesg = resize!(buffer, mesg_size)
    return mesg_type, mesg
end

hex(b::Unsigned) = string(b, base=16)
hex(c::Char) = hex(Integer(c))

@noinline malformed_message(c::Char, b::UInt8) =
    YakError("malformed message, expecting a '$c' (ASCII 0x$(hex(c))), got 0x$(hex(b))")

@noinline malformed_message(s::AbstractString, b::UInt8) =
    YakError("malformed message, expecting $s, got 0x$(hex(b))")

end # module

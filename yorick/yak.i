/*
 * Yak is *yet another kind* of messaging system.
 *
 * This file implements the message protocol, a simple Yak server executiong Yorick
 * commands, and the methods for Yorick clients.
 *
 * Server side
 * ===========
 *
 * A server is started by `yak_start`, stopped by `yak_shutdown`.
 *
 *
 * Client side
 * ===========
 *
 * To connect a client:
 *
 *     sock = yak_connect(port);
 *
 * with `port` the port number where the server is listening. The connection is
 * automatically closed when `sock` is no longer used. The connection may be explicitly
 * closed by calling `close, sock`.
 *
 * To evaluate an expression:
 *
 *     result = yak_send(sock, expr);
 *     yak_send, sock, expr;
 *
 * Example:
 *
 *     val = yak_send(sock, "varname");     // retrieve the value of a global variable
 *     yak_send, sock, "fma";               // call a sub-routine with no arguments
 *     yak_send, sock, "pli, random(4,5)";  // call a sub-routine with arguments
 *     val = yak_send(sock, "sqrt(x) + y"); // evaluate expression
 *
 * Restrictions:
 *
 * - the expression to evaluate must only involve global symbols;
 * - the expression to evaluate must consist in a single statement;
 * - the result is returned as a string.
 *
 *
 * Message format
 * ==============
 *
 * The protocol is simple and based on textual messages of the form (using shell syntax):
 *
 *     "${id}:${len}\n${mesg}\n"
 *
 *  where `${id}` is a single ASCII character specifying the type of the message: `X` for
 *  an eXpression to be evaluated, `E` for an Error, `R` for a Result, `${len}` is the
 *  length of the message content (in bytes, not accounting for the final newline), `\n`
 *  is a newline character (ASCII 0x0a) and `${mesg}` is the message content.
 *
 *  A server only responds to messages of type `X`. Other messages are just printed.
 *
 *  A client sends messages of type `X` and receives answers of type `R` (in case of
 *  success) or `E` (in case of error).
 *
 * Implementation notes
 * ====================
 *
 * When a callback is called with no pending data to receive, it means that connection
 * has been closed by peer.
 *
 * In a callback, commands like `pause` are not allowed.
 *
 * Calls to `sockrecv` are blocking.
 */

local _yak_debug, _yak_server;
if (is_void(_yak_debug)) _yak_debug = 1n; // do not change value in case of multiple includes
_yak_server = [];

func yak_shutdown
/* DOCUMENT yak_shutdown;

     Close Yak server listening connection. Connected clients, if any, can still send
     requests but no new clients can connect.

   SEE ALSO: yak_start, yak_get_server_port.
 */
{
    extern _yak_server;
    if (! is_void(_yak_server)) {
        close, _yak_server;
        _yak_server = [];
    }
}

func yak_start(port)
/* DOCUMENT port = yak_start();
         or yak_start, port;

     Start Yak server on port number `port`. If port number is unspecified, a randomly
     chosen unused port number is use. If called as a function, the port number is
     returned. If called as a subroutine, a message is printed indicating the port number.

   SEE ALSO: yak_shutdown, yak_get_server_port.
 */
{
    extern _yak_server;
    if (! is_void(_yak_server)) {
        error, "server already started";
    }
    if (is_void(port)) {
        port = 0;
    }
    _yak_server = socket(port, _yak_listen_callback);
    if (am_subroutine()) {
        yak_info, swrite(format="Server listening on port %d", _yak_server.port);
    } else {
        return _yak_server.port;
    }
}

func yak_get_server_port(void)
/* DOCUMENT port = yak_get_server_port();

     Return port number of current Yak server or 0 if no server is listening.

   SEE ALSO: yak_start, yak_shutdown.
 */
{
    extern _yak_server;
    if (is_void(_yak_server)) {
        return 0;
    } else {
        return _yak_server.port;
    }
}

func yak_get_value(name) { return symbol_exists(name) ? symbol_def(name) : []; }
/* DOCUMENT val = yak_get_value(name);

     Yield the value of a symbol in the caller's scope. Result is `[]` if symbol does not
     exist.
 */

func yak_to_text(data)
/* DOCUMENT str = yak_to_text(data);

     Convert `data` to its textual representation (for Yorick's parser).

   SEE ALSO: yak_send, print.
 */
{
    str = print(data);
    return (numberof(str) == 1) ? str(1) : sum(str);
}

func yak_connect(port)
/* DOCUMENT sock = yak_connect(port);

     Connect to Yorick server on `port`. The connection is automatically closed when
     `sock` is no longer referenced but may be explicitly closed by `close, sock`.

   SEE ALSO: yak_send.
 */
{
    return socket(-, port);
}

func yak_send(sock, expr)
/* DOCUMENT str = yak_send(sock, expr);

     This function sends a Yorick expression `expr` as a string to be evaluated by the
     peer server on socket `sock` and returns a string result, `str`. Expression `expr`
     can be one of:

     - `var` to retrieve the value of the global variable `var`;

     - `sub` or `sub, arg1, arg2, ...` to call the sub-routine `sub` without or with
       arguments, an empty string is returned;

     - a simple expression whose result is returned.

     Note that expression should only involve literals or global symbols.

   SEE ALSO: yak_connect.
 */
{
    if (! is_string(expr) || ! is_scalar(expr)) {
        error, "expression must be a scalar string";
    }
    _yak_send_message, sock, 'X', expr;
    local id;
    str = _yak_recv_message(sock, id);
    if (id == 'R') {
        // Normal result.
        return str;
    } else if (id == 'E') {
        // Some error occurred.
        error, str;
    } else {
        // Some unexpected result.
        error, swrite("unexpected message type = %d", id);
    }
}

func _yak_send_message(sock, id, mesg)
/* DOCUMENT err = _yak_send_message(sock, id, mesg);
         or _yak_send_message, sock, id, mesg;

     Send formated message to peer via socket `sock` using a simple protocol: the snet
     bytes are `ID:LEN\nMESG\n` where `ID` is the message identifier (a character), `LEN`
     is `strlen(mesg)` in decimal format, `\n` is a newline character (ASCII 0x0a), and
     `MESG` is the message.

     When called as a function, no errors get thrown: a void result is returned on
     success, an error message is returned on error.

     When called as a sub-routine, errors are thrown.

   SEE ALSO: yak_send, _yak_recv_message.
 */
{
    buffer = strchar(swrite(format="%c:%d\n%s", id, strlen(mesg), mesg));
    buffer(0) = '\n';
    nbytes = socksend(sock, buffer);
    if (nbytes != sizeof(buffer)) {
        close, sock;
        err = nbytes < 0 ? "`socksend` error" : "connection closed by peer";
        if (am_subroutine()) {
            error, err;
        }
        return err;
    }
}

func _yak_recv_message(sock, &id)
/* DOCUMENT local id;
            str = _yak_recv_message(sock, id);

     Private function to receive a message from a connected peer. This function does not
     throw errors because it may be used in a callback. Returned value is a string, `str`.
     If an error occurs, `str` is the error message; otherwise, `str` is the message
     content. Caller's variable `id` is set to indicate an error (`id < 0`) or to identify
     the type of the message.

   SEE ALSO: yak_send, _yak_send_message;
 */
{
    // In case of error, the error message is returned and early return can only occur on
    // error.
    id = 'E'; // for now, assume some error occured

    // Read the message header. The minimal header size if 4 bytes. Since calls to
    // `sockrecv` are blocking, any truncated results mean that peer has closed the
    // connection.
    zero = long('0');
    newline = '\n';
    buffer = array(char, 4);
    nbytes = sockrecv(sock, buffer);
    if (nbytes < sizeof(buffer)) {
        return _yak_sockrecv_error(nbytes);
    }
    type = buffer(1); // message type
    size = buffer(3) - zero;
    if (buffer(2) != ':' || size < 0 || size > 9) {
        return _yak_malformed_message();
    }
    local byte;
    for (index = 4; ; ++index) { // Until first newline separator is found...
        if (index <= sizeof(buffer)) {
            byte = buffer(index);
        } else {
            // Read one more byte.
            nbytes = sockrecv(sock, byte);
            if (nbytes < 1) {
                return _yak_sockrecv_error(nbytes);
            }
        }
        if (byte == newline) {
            break;
        }
        digit = byte - zero;
        if (digit < 0 || digit > 9) {
            return _yak_malformed_message();
        }
        size = digit + 10*size;
    }

    // Read the remainingg part of the message, that is its content.
    ++size; // for the final newline
    if (sizeof(buffer) != size) {
        buffer = array(char, size);
    }
    nbytes = sockrecv(sock, buffer);
    if (nbytes < sizeof(buffer)) {
        return _yak_sockrecv_error(nbytes);
    }
    if (buffer(0) != newline) {
        // Final newline is missing.
        return _yak_malformed_message();
    }
    buffer(0) = 0;
    id = type; // there were no errors
    return strchar(buffer);
}

func _yak_connection_closed_by_peer(void) {
    return "connection closed by peer";
}
func _yak_malformed_message(void) {
    return "malformed message";
}
func _yak_sockrecv_error(nbytes) {
    return nbytes < 0 ? "`sockrecv` error" : _yak_connection_closed_by_peer();
}
func _yak_sockend_error(nbytes) {
    return nbytes < 0 ? "`socksend` error" : _yak_connection_closed_by_peer();
}

func _yak_listen_callback(listener)
/* DOCUMENT _yak_listen_callback, sock;

     Private callback called when a client connects to the server.

   SEE ALSO: yak_start.
 */
{
    sock = listener(_yak_recv_callback);
    yak_info, swrite(format="Client connected on port %d", sock.port);
}

func _yak_recv_callback(_yak_sock)
/* DOCUMENT _yak_recv_callback, sock;

     Private callback called to process data sent by a client.

   SEE ALSO: yak_start.
 */
{
    // IMPORTANT: All symbols must be prefixed with _yak_ to avoid collisions in
    //            evaluating code.
    local _yak_id;
    _yak_mesg = _yak_recv_message(_yak_sock, _yak_id);
    if (_yak_id == 'X') {
        _yak_result = _yak_eval(_yak_mesg, _yak_id);
        //if (is_void(_yak_result)) {
        //    _yak_result = "";
        //} else
        if (! is_string(_yak_result) || ! is_scalar(_yak_result)) {
            _yak_result = yak_to_text(_yak_result);
        }
        _yak_err = _yak_send_message(_yak_sock, _yak_id, _yak_result);
        if (! is_void(_yak_err)) {
            _yak_error, _yak_err;
        }
    } else if (_yak_id == 'E') {
        _yak_error, _yak_mesg;
    } else {
        write, format="YAK INFO (%c): %s\n", _yak_id, _yak_mesg;
    }
}

local _yak_eval_result, _yak_eval_status;
local _yak_eval_assign, _yak_eval_expression, _yak_eval_subroutine;
func _yak_eval(_yak_eval_expr, &_yak_eval_id)
/* DOCUMENT res = _yak_eval(expr, &id);

     Private subroutine called by the server to evaluate an expression. `expr` must be a
     simple Yorick expression, there following syntaxes are supported:

         var    // a simple global variable name, result is variable's value
         sub    // a simple call to a subroutine without arguments, result is []
         f(a1,a2,...)

     If client want to evaluate several statements (e.g. separated by ...)

     yak_variable, "var = expr";
     yak_variable, "var";
     yak_call_function, "f(...)";
     yak_call_subroutine, "sub, ...";

   SEE ALSO: yak_success, yak_failure, yak_send, exec.
 */
{
    // Manage to report errors.
    _yak_eval_id = 'R';
    if (catch(-1)) {
        // Some runtime error occurred.
        _yak_eval_id = 'E';
        return catch_message;
    }

    // Evaluate the expression according to its inferred type. An auxiliary function,
    // `_yak_eval_fun`, is compiled and called to correctly handle statements like
    // `catch` (see Yorick's `exec` function).
    local _yak_eval_func;
    _yak_eval_subroutine = 0n; // expression to evaluate is a subroutine call?
    _yak_eval_head = _yak_eval_tail = string();
    _yak_eval_count = sread(_yak_eval_expr, format=" %[_a-zA-Z0-9] %[^ ]", _yak_eval_head,
                             _yak_eval_tail);
    if (_yak_eval_count >= 1 && ! strglob("[0-9]*", _yak_eval_head)) {
        // First token is a valid symbol.
        if (_yak_eval_count == 1) {
            // Code looks like "sub", a sub-routine call, or "var" a simple variable. We
            // mimic Yorick's REPL behavior: if symbol is defined and is a function, call
            // it as a subroutine; otherwise, returns its value (possibly void).
            _yak_eval_value = yak_get_value(_yak_eval_head);
            if (is_func(_yak_eval_value) != 0) {
                // Assume a subroutine call.
                _yak_eval_subroutine = 1n;
            } else {
                return _yak_eval_value;
            }
        } else if (strglob(",*", _yak_eval_tail)) {
            // Code looks like "sub, ...", a sub-routine call with arguments.
            _yak_eval_subroutine = 1n;
        } else if (strglob("=*", _yak_eval_tail) && ! strglob("==*", _yak_eval_tail)) {
            // Code looks like "var = expr", a simple variable assignation. The variable
            // must be declared as "extern" before evaluating the expression otherwise,
            // calling the subroutine will not assign the global variable.
            _yak_compile_code, ("func _yak_eval_func { extern " + _yak_eval_head + "; "
                                 + _yak_eval_expr + "; }");
            _yak_eval_func;
            return [];
        }
    }
    if (_yak_eval_subroutine) {
        // Evaluate a subroutine call.
        _yak_compile_code, ("func _yak_eval_func { " + _yak_eval_expr + "; }");
        _yak_eval_func;
        return [];
    } else {
        // Evaluate a simple expression and return its result.
        _yak_compile_code, ("func _yak_eval_func(_yak_void) { return " +
                             _yak_eval_expr + "; }");
        return _yak_eval_func();
    }
}

func _yak_compile_code(_yak_code)
{
    if (_yak_debug) {
        write, format="YAK DEBUG: compile code \"%s\"\n", _yak_code;
    }
    include, [_yak_code], 1;
}

func _yak_error(mesg)
{
    write, format="YAK ERROR: %s\n", mesg;
}

func yak_info(mesg)
{
    write, format="YAK INFO: %s\n", mesg;
}

if (batch()) {
    yak_start;
}

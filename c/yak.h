#ifndef YAK_H_
#define YAK_H_ 1

/**
 * Structure representing a Yak connection.
 *
 * An object of this type has the following members:
 *
 * - `conn.peer` is the name of the peer.
 * - `conn.port` is the port number of the service.
 * - `conn.sock` is the file descriptor of the connected socket.
 */
typedef struct yak_connection_ {
    const char* peer;
    int sock;
    int port;
} yak_connection;

/**
 * @def YAK_CONNECTION_INITIALIZER
 *
 * Static initializer of a Yak connection.
 *
 * ``` c
 * yak_connection conn = YAK_CONNECTION_INITIALIZER;
 * ```
 */
#define YAK_CONNECTION_INITIALIZER = (yak_connection){NULL, -1, 0}

/**
 * Check whether a Yak connection is open.
 *
 * @param conn  The connection (can be `NULL`).
 *
 * @return `1` if `conn` is non-`NULL` and open; `0` otherwise.
 */
extern int yak_is_open(yak_connection* conn);

/**
 * Initialize a Yak connection.
 *
 * This is the same as setting the content of `conn` with `YAK_CONNECTION_INITIALIZER`.
 *
 * @param conn  The connection to initialize (cannot be `NULL`).
 *
 * @return The initialized connection.
 */
extern yak_connection* yak_init(yak_connection* conn);

/**
 * Close a Yak connection.
 *
 * If `conn` is `NULL`, nothing is done. Otherwise, the socket associated with the
 * connection is closed if it is open, any associated resources are released, and the
 * members of `conn` are set as if `conn` was initialized with `YAK_CONNECTION_INITIALIZER`.
 *
 * @param conn  The connection to close (can be `NULL`).
 *
 * @return `0` on success, the value of `errno` on error.
 */
extern int yak_close(yak_connection* conn);

/**
 * Open a Yak connection.
 *
 * On entry, the content of `conn` is irrelevant. There is no attempt to automatically close
 * the connection.
 *
 * @param conn  The connection structure to initialize (not `NULL`).
 * @param host  The host to connect to (assumed to be `"localhost"` if `NULL`).
 * @param port  The port number of the service.
 *
 * @return `0` on success, the value of `errno` on error.
 */
extern int yak_connect(yak_connection* conn, const char* host, int port);

/**
 * Send a message to a Yak connection.
 *
 * @param conn   The connection.
 * @param type   The address to store the Yak message type.
 * @param data   The buffer to store the Yak message data.
 * @param len    The number of bytes to send in `data`.
 *
 * @note The connection is always closed on error even though nothing has been written to
 *       the socket. This is needed to signal the peer that something wrong has occurred on
 *       the other side. Otherwise, the peer could be blocked waiting for an answer that
 *       will never come.
 */
extern int yak_send_message(yak_connection* conn, char type, const void* data, long len);

/**
 * Receive a message from a Yak connection into a given buffer.
 *
 * @param conn   The connection.
 * @param type   The address to store the message type.
 * @param data   The buffer to store the message data.
 * @param len    The address to store the number of bytes stored in `data`.
 * @param maxlen The maximum number of bytes that can be stored in `data`.
 *
 * @note The connection is always closed on error even though nothing has been read from the
 *       socket. This is needed to signal to the peer that something wrong has occurred on
 *       the other side. Otherwise, the peer could be blocked waiting for its message to
 *       be sent.
 */
extern int yak_recv_message_in_buffer(yak_connection* conn, char* type, void* data,
                                      long* len, long maxlen);

/**
 * Receive a message from a Yak connection.
 *
 * Unless `*data == NULL`, it is the caller's responsibility to call `free(*data)` to free
 * the memory allocated for the message data .
 *
 * The connection is closed (and `*data` is set to `NULL`) in case of error.
 *
 * @param conn  The connection.
 * @param type  The address to store the message type.
 * @param data  The address to store the allocated memory for the message data.
 * @param len   The address to store the number of bytes allocated for the message data.
 *
 * @return `0` on success; an error code otherwise.
 *
 * @note The connection is always closed on error even though nothing has been read from the
 *       socket. This is needed to signal to the peer that something wrong has occurred on
 *       the other side. Otherwise, the peer could be blocked waiting for its message to
 *       be sent.
 */
extern int yak_recv_message(yak_connection* conn, char* type, void** data, long* len);

#endif /* YAK_H_ */

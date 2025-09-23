#include "yak.h"

#include <errno.h>
#include <netdb.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

typedef struct message_info_ {
    long len;
    char type;
} message_info;

static long print_integer(char* buf, long len, long val);
static long recv_data(yak_connection* conn, void *data, long len);
static long send_data(yak_connection* conn, const void *data, long len);
static int recv_message_info(yak_connection* conn, message_info* msg);
static int recv_message_data(yak_connection* conn, void* data, long len);
static int get_errno(int def);
static struct addrinfo* listaddrinfo(const char* host, int port, bool passive);

/* Yield system error code `errno` or `def` if `errno` is zero. */
static int get_errno(int def)
{
    int val = errno;
    return val == 0 ? def : val;
}

/* Print decimal number `val` into buffer `buf` with at least `len` characters. Return
   length of written string (not including final '\0') or -1 if `buf` is not large
   enough. */
static long print_integer(char* buf, long len, long val)
{
    long i, j, r, n;

    /* Write least significant digit and sign if `val` is negative. This also avoids
       overflows with `-val`. */
    if (val >= 0) {
        if (len < 2) {
            return -1;
        }
        buf[0] = '0' + (val % 10);
        j = 0;
        r = val/10;
    } else {
        if (len < 3) {
            return -1;
        }
        buf[0] = '-';
        buf[1] = '0' - (val % 10);
        j = 1;
        r = -(val/10);
    }
    i = j;

    /* Write other digits form the 2nd least to the most significant one. */
    while (r > 0) {
        if (++i >= len) {
            return -1;
        }
        buf[i] = '0' + (r % 10);
        r /= 10;
    }
    n = i + 1;
    if (n >= len) {
        return -1;
    }
    buf[n] = '\0';

    /* Reverse order of written digits. */
    while (j < i) {
        char c = buf[i];
        buf[i] = buf[j];
        buf[j] = c;
        ++j;
        --i;
    }

    /* Return length of written string. */
    return n;
}

int yak_is_open(yak_connection* conn)
{
    return conn != NULL && conn->sock >= 0;
}

yak_connection* yak_init(yak_connection* conn)
{
    if (conn != NULL) {
        memset(conn, 0, sizeof(*conn));
        conn->sock = -1;
    }
    return conn;
}

int yak_close(yak_connection* conn)
{
    int status = 0;
    if (conn != NULL) {
        if (conn->sock != -1) {
            if (conn->sock >= 0) {
                if (close(conn->sock) != 0) {
                    status = errno;
                }
            }
            conn->sock = -1;
        }
        if (conn->peer != NULL) {
            free((void*)conn->peer);
            conn->peer = NULL;
        }
        conn->port = 0;
    }
    return status;
}

static struct addrinfo* listaddrinfo(const char* host, int port, bool passive)
{
    if (host == NULL) {
        errno = EFAULT;
        return NULL;
    }
    if (port < 0 || port > 65535) {
        errno = EINVAL;
        return NULL;
    }
    char service[8];
    if (print_integer(service, 8, port) < 0) {
        errno = EOVERFLOW;
        return NULL;
    }
    struct addrinfo hints, *list;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_CANONNAME;
    if (passive) {
        hints.ai_flags |= AI_PASSIVE;  /* will call bind, not connect */
    }
    if (getaddrinfo(host, service, &hints, &list) != 0) {
        return NULL;
    }
    return list;
}

int yak_connect(yak_connection* conn, const char* host, int port)
{
    if (conn == NULL) {
        return EFAULT;
    }
    yak_init(conn);
    if (host == NULL) {
        host = "127.0.0.1"; /* more certain than "localhost"? */
    }
    struct addrinfo* list = listaddrinfo(host, port, false);
    if (list != NULL) {
        fprintf(stderr, "canonname=\"%s\"\n", list->ai_canonname);
    }
    for (struct addrinfo* ai = list; ai != NULL; ai = ai->ai_next) {
        int sock = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (sock != -1) {
            if (connect(sock, ai->ai_addr, ai->ai_addrlen) != -1) {
                conn->sock = sock;
                break;
            }
            (void)close(sock); /* FIXME ignore errors here? */
        }
    }
    if (list != NULL) {
        freeaddrinfo(list);
    }
    if (conn->sock == -1) {
        return EACCES;
    }
    conn->peer = strdup(host);
    if (conn->peer == NULL) {
        int status = get_errno(ENOMEM);
        (void)yak_close(conn);
        return status;
    }
    conn->port = port;
    return 0;
}

/* return value <0 for error, <len means socket recv side closed */
static long recv_data(yak_connection* conn, void *data, long len)
{
    char *ptr = data;
    while (len > 0) {
        ssize_t n = recv(conn->sock, ptr, len, 0);
        if (n < 0) {
            /* An error occurred. */
            return -1;
        }
        if (n == 0) {
            /* Socket closed by peer or no more data available. */
            break;
        }
        ptr += n;
        len -= n;
    }
    return ptr - (char *)data;
}

static long send_data(yak_connection* conn, const void *data, long len)
{
    const char *ptr = data;
    while (len > 0) {
        ssize_t n = send(conn->sock, ptr, len, 0);
        if (n < 0) {
            /* An error occurred. */
            return -1;
        }
        if (n == 0) {
            /* Socket closed by peer or no more data available. */
            break;
        }
        ptr += n;
        len -= n;
    }
    return ptr - (const char *)data;
}

int yak_send_message(yak_connection* conn, char type, const void* data, long len)
{
    /* Check arguments. */
    if (conn == NULL) {
        return EFAULT;
    }
    if (conn->sock < 0) {
        return EBADF;
    }
    int status = 0;
    if (len < 0) {
        status = EINVAL;
        goto error;
    }
    if (data == NULL && len > 0) {
        status = EFAULT;
        goto error;
    }

    /* Send the message header to the peer. */
    char header[32];
    header[0] = type;
    header[1] = ':';
    long ndigits = print_integer(header + 2, sizeof(header) - 2, len);
    if (ndigits < 0 || ndigits + 3 >= sizeof(header)) {
        status = EOVERFLOW;
        goto error;
    }
    header[ndigits + 2] = '\n';
    header[ndigits + 3] = '\0'; /* this is not really needed */
    long nbytes = send_data(conn, header, ndigits + 3);
    if (nbytes != ndigits + 3) {
        status = get_errno(nbytes < 0 ? EIO : ECONNRESET);
        goto error;
    }

    /* Send the message data to the peer: the data and a final '\n'. */
    if (len > 0) {
        nbytes = send_data(conn, data, len);
        if (nbytes != len) {
            status = get_errno(nbytes < 0 ? EIO : ECONNRESET);
            goto error;
        }
    }
    nbytes = send_data(conn, "\n", 1);
    if (nbytes != 1) {
        status = get_errno(nbytes < 0 ? EIO : ECONNRESET);
        goto error;
    }
    return 0;

    /* An error has occurred. */
error:
    yak_close(conn);
    return status;
}

static int recv_message_info(yak_connection* conn, message_info* hdr)
{
    /* Initialize. */
    hdr->len = 0;
    hdr->type = '\0';

    /* Message header has at least 4 bytes. */
    char buf[4];
    long nbytes = recv_data(conn, buf, 4);
    if (nbytes != 4) {
        /* Error or short header. */
        return nbytes < 0 ? get_errno(EIO) : EBADMSG;
    }
    char type = buf[0];
    if (buf[1] != ':') {
        /* Invalid header. */
        return EBADMSG;
    }
    char c = buf[2];
    if ((c < '0') || (c > '9')) {
        /* Invalid header. */
        return EBADMSG;
    }
    long len = c - '0';
    c = buf[3];
    while (c != '\n') {
        if ((c >= '0') && (c <= '9')) {
            long prev = len;
            len = (c - '0') + 10*len;
            if (len < prev) {
                /* Integer overflow. */
                return EOVERFLOW;
            }
        } else {
            /* Unexpected character. */
            return EBADMSG;
        }
        /* Receive next byte. */
        nbytes = recv_data(conn, &c, 1);
        if (nbytes != 1) {
            /* Error or short header. */
            return nbytes < 0 ? get_errno(EIO) : EBADMSG;
        }
    }
    hdr->len = len;
    hdr->type = type;
    return 0;
}

static int recv_message_data(yak_connection* conn, void* data, long len)
{
    long nbytes;
    if (len > 0) {
        /* Read message content. */
        nbytes = recv_data(conn, data, len);
        if (nbytes != len) {
            /* Error or short data. */
            return nbytes < 0 ? get_errno(EIO) : EBADMSG;
        }
    }
    /* Read final '\n'. */
    char buf[1];
    nbytes = recv_data(conn, buf, 1);
    if (nbytes != 1) {
        /* Error or short data. */
        return nbytes < 0 ? get_errno(EIO) : EBADMSG;
    }
    if (buf[0] != '\n') {
        return EBADMSG;
    }
    return 0;
}

int yak_recv_message_in_buffer(yak_connection* conn, char* type, void* data,
                               long* len, long maxlen)
{
    /* Initialize outputs. */
    if (type != NULL) {
        *type = '\0';
    }
    if (len != NULL) {
        *len = 0;
    }

    /* Check connection. */
    if (conn == NULL) {
        return EFAULT;
    }
    if (conn->sock < 0) {
        return EBADF;
    }

    /* Check other arguments. Any error below will result in the connection being closed. */
    int status = 0;
    if (maxlen < 0) {
        status = EINVAL;
        goto error;
    }
    if (data == NULL && maxlen > 0) {
        status = EFAULT;
        goto error;
    }

    /* Read message header. */
    message_info msg;
    status = recv_message_info(conn, &msg);
    if (status != 0) {
        goto error;
    }
    if (msg.len > maxlen) {
        status = EMSGSIZE;
        goto error;
    }

    /* Read message data. */
    status = recv_message_data(conn, data, msg.len);
    if (status != 0) {
        goto error;
    }

    /* Success. */
    if (type != NULL) {
        *type = msg.type;
    }
    if (len != NULL) {
        *len = msg.len;
    }
    return 0;

    /* An error has occurred. */
error:
    yak_close(conn);
    return status;
}


int yak_recv_message(yak_connection* conn, char* type, void** data, long* len)
{
    /* Initialize outputs. */
    if (type != NULL) {
        *type = '\0';
    }
    if (data != NULL) {
        *data = NULL;
    }
    if (len != NULL) {
        *len = 0;
    }

    /* Check connection. */
    if (conn == NULL || data == NULL) {
        return EFAULT;
    }
    if (conn->sock < 0) {
        return EBADF;
    }

    /* Read message header. Any error below will result in the connection being closed. */
    message_info msg;
    int status = recv_message_info(conn, &msg);
    if (status != 0) {
        goto error;
    }

    /* Allocate data buffer and read message data. */
    if (msg.len > 0) {
        void* buf = malloc(msg.len);
        if (buf == NULL) {
            status = get_errno(ENOMEM);
            goto error;
        }
        status = recv_message_data(conn, buf, msg.len);
        if (status == 0 && data != NULL) {
            *data = buf;
        } else {
            free(buf);
            if (status != 0) {
                goto error;
            }
        }
    }

    /* Success. */
    if (type != NULL) {
        *type = msg.type;
    }
    if (len != NULL) {
        *len = msg.len;
    }
    return 0;

    /* An error has occurred. */
error:
    yak_close(conn);
    return status;
}

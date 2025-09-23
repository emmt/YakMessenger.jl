srcdir=.

default: yak-client

yak.o: $(srcdir)/yak.c $(srcdir)/yak.h
	$(CC) -c -I$(srcdir) $(CFLAGS) "$<" -o "$@"

yak-client.o: $(srcdir)/yak-client.c $(srcdir)/yak.h
	$(CC) -c -I$(srcdir) $(CFLAGS) "$<" -o "$@"

yak-client: yak-client.o yak.o
	$(CC) $(LDFLAGS) $^ -o "$@" -lreadline

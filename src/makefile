CC=g++
CFLAGS=-c -std=c++11 -pthread
LDFLAGS=-std=c++11 -pthread
SOURCES=$(wildcard *.cpp)
OBJECTS=$(SOURCES:.cpp=.o)
EXECUTABLE=xlxd
PREFIX ?= /xlxd

all: $(SOURCES) $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@

.cpp.o:
	$(CC) $(CFLAGS) $< -o $@

clean:
	$(RM) $(EXECUTABLE) *.o

install:
	mkdir -p $(PREFIX)/{bin,etc}
	cp -f $(EXECUTABLE) $(PREFIX)/bin/
	cp ../config/xlxd.blacklist $(PREFIX)/etc/xlxd.blacklist
	cp ../config/xlxd.whitelist $(PREFIX)/etc/xlxd.whitelist
	cp ../config/xlxd.interlink $(PREFIX)/etc/xlxd.interlink
	cp ../config/xlxd.terminal $(PREFIX)/etc/xlxd.terminal

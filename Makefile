CC = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2

all: assembler

assembler: assembler.cpp
	$(CC) $(CXXFLAGS) -o assembler assembler.cpp

test: assembler
	./assembler example.asm example.lst

clean:
	rm -f assembler example.lst

.PHONY: all test clean

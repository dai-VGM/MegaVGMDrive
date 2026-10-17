CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -std=c++14 -Wall -Wextra -Wpedantic
LDFLAGS ?=

.PHONY: all test clean

all: megavgm_autoplay2

megavgm_autoplay2: main.cpp autoplay2.cpp autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) main.cpp autoplay2.cpp $(LDFLAGS) -o $@

test_autoplay2: test_autoplay2.cpp autoplay2.cpp autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) test_autoplay2.cpp autoplay2.cpp $(LDFLAGS) -pthread -o $@

test: test_autoplay2
	./test_autoplay2

clean:
	rm -f megavgm_autoplay2 test_autoplay2

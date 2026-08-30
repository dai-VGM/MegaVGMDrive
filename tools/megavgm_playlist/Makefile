CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -std=c++14 -Wall -Wextra -Wpedantic
LDFLAGS ?=

AUTOPLAY2_DIR := ../megavgm_autoplay2
SOURCES := main.cpp playlist.cpp $(AUTOPLAY2_DIR)/autoplay2.cpp

.PHONY: all test clean

all: megavgm_playlist

megavgm_playlist: $(SOURCES) playlist.h $(AUTOPLAY2_DIR)/autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SOURCES) $(LDFLAGS) -o $@

test_playlist: test_playlist.cpp playlist.cpp playlist.h \
		$(AUTOPLAY2_DIR)/autoplay2.cpp $(AUTOPLAY2_DIR)/autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) test_playlist.cpp playlist.cpp \
		$(AUTOPLAY2_DIR)/autoplay2.cpp $(LDFLAGS) -o $@

test: test_playlist
	./test_playlist

clean:
	rm -f megavgm_playlist test_playlist

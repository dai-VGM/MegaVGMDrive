CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -std=c++14 -Wall -Wextra -Wpedantic
LDFLAGS ?=

AUTOPLAY2_DIR := ../megavgm_autoplay2
SOURCES := main.cpp playlist.cpp playlist_control.cpp playback_mode.cpp \
	$(AUTOPLAY2_DIR)/autoplay2.cpp

.PHONY: all test clean

all: megavgm_playlist megavgm_ctl

megavgm_playlist: $(SOURCES) playlist.h playlist_control.h \
		$(AUTOPLAY2_DIR)/autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SOURCES) $(LDFLAGS) -o $@

megavgm_ctl: ctl.cpp playlist_control.cpp playback_mode.cpp playlist_control.h playback_mode.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) ctl.cpp playlist_control.cpp playback_mode.cpp \
		$(LDFLAGS) -o $@

test_playlist: test_playlist.cpp playlist.cpp playlist_control.cpp playback_mode.cpp playlist.h \
		playlist_control.h \
		$(AUTOPLAY2_DIR)/autoplay2.cpp $(AUTOPLAY2_DIR)/autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) test_playlist.cpp playlist.cpp \
		playlist_control.cpp playback_mode.cpp \
		$(AUTOPLAY2_DIR)/autoplay2.cpp $(LDFLAGS) -o $@

test_playlist_control: test_playlist_control.cpp playlist_control.cpp playback_mode.cpp \
		playlist_control.h playback_mode.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) test_playlist_control.cpp \
		playlist_control.cpp playback_mode.cpp $(LDFLAGS) -o $@

test_playback_mode: test_playback_mode.cpp playback_mode.cpp playback_mode.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) test_playback_mode.cpp playback_mode.cpp \
		$(LDFLAGS) -o $@

test: test_playlist test_playlist_control test_playback_mode
	./test_playlist
	./test_playlist_control
	./test_playback_mode

clean:
	rm -f megavgm_playlist megavgm_ctl test_playlist test_playlist_control test_playback_mode

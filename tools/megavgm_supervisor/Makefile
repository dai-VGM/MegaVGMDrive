CXX ?= c++
CPPFLAGS ?=
CXXFLAGS ?= -O2 -std=c++14 -Wall -Wextra -Wpedantic -Werror
LDFLAGS ?=

COMMON_SOURCES := supervisor.cpp runtime_support.cpp sha256.cpp
AUTOPLAY_SOURCE := ../megavgm_autoplay2/autoplay2.cpp
SUPERVISOR_SOURCES := main.cpp linux_runtime.cpp $(COMMON_SOURCES) $(AUTOPLAY_SOURCE)
TEST_SOURCES := test_supervisor.cpp $(COMMON_SOURCES)

.PHONY: all test clean

all: megavgm_supervisor

megavgm_supervisor: $(SUPERVISOR_SOURCES) supervisor.h runtime_support.h \
		linux_runtime.h sha256.h ../megavgm_autoplay2/autoplay2.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(SUPERVISOR_SOURCES) \
		$(LDFLAGS) -o $@

test_supervisor: $(TEST_SOURCES) supervisor.h runtime_support.h sha256.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(TEST_SOURCES) $(LDFLAGS) -o $@

test: test_supervisor
	./test_supervisor

clean:
	rm -f megavgm_supervisor test_supervisor

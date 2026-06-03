CXX ?= c++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -O2

TARGET = vgm_inspector
SRC = vgm_inspector.cpp

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)

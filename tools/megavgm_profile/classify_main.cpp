#include "profile.h"
#include <iostream>
int main(int argc, char **argv) {
    if (argc < 3) { std::cerr << "Usage: classify <approved-root> <vgm>...\n"; return 2; }
    int result = 0;
    for (int i=2; i<argc; ++i) {
        const auto c = megavgm_profile::classify_file(argv[i], argv[1]);
        std::cout << megavgm_profile::name(c.profile) << '\t' << c.commands << '\t' << argv[i] << '\t' << c.detail << '\n';
        if (c.profile != megavgm_profile::Profile::A && c.profile != megavgm_profile::Profile::B) result = 1;
    }
    return result;
}

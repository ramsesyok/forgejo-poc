#include <iostream>
#include <string_view>

#include "version.hpp"

int main(int argc, char* argv[]) {
    if (argc == 1) {
        std::cout << "Hello from Forgejo Actions!\n";
        return 0;
    }

    if (argc == 2 && std::string_view(argv[1]) == "--version") {
        std::cout << "cpp-release-sample " << SAMPLE_VERSION << '\n';
        return 0;
    }

    std::cerr << "Usage: cpp-release-sample [--version]\n";
    return 2;
}

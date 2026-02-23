/*
 * Two-Pass Assembler
 * Курсовая работа
 *
 * Supported instructions:
 *   MOV  reg, reg/imm    - move value
 *   ADD  reg, reg/imm    - add
 *   SUB  reg, reg/imm    - subtract
 *   MUL  reg, reg/imm    - multiply
 *   DIV  reg, reg/imm    - divide
 *   AND  reg, reg/imm    - bitwise AND
 *   OR   reg, reg/imm    - bitwise OR
 *   XOR  reg, reg/imm    - bitwise XOR
 *   NOT  reg             - bitwise NOT
 *   CMP  reg, reg/imm    - compare (sets flags)
 *   JMP  label           - unconditional jump
 *   JZ   label           - jump if zero
 *   JNZ  label           - jump if not zero
 *   JG   label           - jump if greater
 *   JL   label           - jump if less
 *   PUSH reg/imm         - push onto stack
 *   POP  reg             - pop from stack
 *   CALL label           - call subroutine
 *   RET                  - return from subroutine
 *   NOP                  - no operation
 *   HLT                  - halt
 *   IN   reg             - read from input
 *   OUT  reg             - write to output
 *
 * Data directives:
 *   DB   value[, value]  - define byte(s)
 *   DW   value[, value]  - define word(s) (2 bytes)
 *
 * Registers: AX, BX, CX, DX, SP, BP
 *
 * Usage: assembler <input.asm> [output.lst]
 */

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Opcode table
// ---------------------------------------------------------------------------

enum class OpType {
    REG_REG,
    REG_IMM,
    REG,
    IMM,
    LABEL,
    NONE
};

struct InstrDef {
    uint8_t opcode;
    int size; // instruction size in bytes
    OpType operandType;
};

// Opcodes (1-byte opcode + operands)
static const std::map<std::string, std::vector<InstrDef>> INSTR_TABLE = {
    {"MOV",  {{0x10, 3, OpType::REG_REG}, {0x11, 4, OpType::REG_IMM}}},
    {"ADD",  {{0x20, 3, OpType::REG_REG}, {0x21, 4, OpType::REG_IMM}}},
    {"SUB",  {{0x30, 3, OpType::REG_REG}, {0x31, 4, OpType::REG_IMM}}},
    {"MUL",  {{0x40, 3, OpType::REG_REG}, {0x41, 4, OpType::REG_IMM}}},
    {"DIV",  {{0x50, 3, OpType::REG_REG}, {0x51, 4, OpType::REG_IMM}}},
    {"AND",  {{0x60, 3, OpType::REG_REG}, {0x61, 4, OpType::REG_IMM}}},
    {"OR",   {{0x70, 3, OpType::REG_REG}, {0x71, 4, OpType::REG_IMM}}},
    {"XOR",  {{0x80, 3, OpType::REG_REG}, {0x81, 4, OpType::REG_IMM}}},
    {"NOT",  {{0x90, 2, OpType::REG}}},
    {"CMP",  {{0xA0, 3, OpType::REG_REG}, {0xA1, 4, OpType::REG_IMM}}},
    {"JMP",  {{0xB0, 3, OpType::LABEL}}},
    {"JZ",   {{0xB1, 3, OpType::LABEL}}},
    {"JNZ",  {{0xB2, 3, OpType::LABEL}}},
    {"JG",   {{0xB3, 3, OpType::LABEL}}},
    {"JL",   {{0xB4, 3, OpType::LABEL}}},
    {"PUSH", {{0xC0, 2, OpType::REG}, {0xC1, 3, OpType::IMM}}},
    {"POP",  {{0xC2, 2, OpType::REG}}},
    {"CALL", {{0xD0, 3, OpType::LABEL}}},
    {"RET",  {{0xD1, 1, OpType::NONE}}},
    {"NOP",  {{0xE0, 1, OpType::NONE}}},
    {"HLT",  {{0xFF, 1, OpType::NONE}}},
    {"IN",   {{0xF0, 2, OpType::REG}}},
    {"OUT",  {{0xF1, 2, OpType::REG}}},
};

// Register encoding
static const std::map<std::string, uint8_t> REG_TABLE = {
    {"AX", 0x00}, {"BX", 0x01}, {"CX", 0x02}, {"DX", 0x03},
    {"SP", 0x04}, {"BP", 0x05},
};

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

struct AssemblyLine {
    int lineNumber;
    std::string label;
    std::string mnemonic;
    std::string operand1;
    std::string operand2;
    std::string raw;
    int address;
    int size;
    bool isData;
    std::string dataDirective; // "DB" or "DW"
    std::vector<int> dataValues;
};

struct Symbol {
    int address;
    int lineNumber;
};

struct AssembledByte {
    int address;
    uint8_t value;
};

// ---------------------------------------------------------------------------
// Utility functions
// ---------------------------------------------------------------------------

static std::string toUpper(const std::string &s) {
    std::string r = s;
    std::transform(r.begin(), r.end(), r.begin(), ::toupper);
    return r;
}

static std::string trim(const std::string &s) {
    size_t start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

static bool isRegister(const std::string &s) {
    return REG_TABLE.count(toUpper(s)) > 0;
}

static bool isImmediate(const std::string &s, int &value) {
    if (s.empty()) return false;
    try {
        size_t pos;
        if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
            value = std::stoi(s, &pos, 16);
            return pos == s.size();
        } else if (s.back() == 'H' || s.back() == 'h') {
            std::string sub = s.substr(0, s.size() - 1);
            value = std::stoi(sub, &pos, 16);
            return pos == sub.size();
        } else if (s.back() == 'B' || s.back() == 'b') {
            std::string sub = s.substr(0, s.size() - 1);
            value = std::stoi(sub, &pos, 2);
            return pos == sub.size();
        } else {
            value = std::stoi(s, &pos, 10);
            return pos == s.size();
        }
    } catch (...) {
        return false;
    }
}

// ---------------------------------------------------------------------------
// Parser: split a source line into components
// ---------------------------------------------------------------------------

static AssemblyLine parseLine(const std::string &raw, int lineNumber) {
    AssemblyLine al;
    al.lineNumber = lineNumber;
    al.raw = raw;
    al.address = 0;
    al.size = 0;
    al.isData = false;

    // Strip comments (';')
    std::string line = raw;
    size_t cpos = line.find(';');
    if (cpos != std::string::npos) line = line.substr(0, cpos);
    line = trim(line);
    if (line.empty()) return al;

    // Check for label (ends with ':')
    size_t colonPos = line.find(':');
    if (colonPos != std::string::npos) {
        al.label = toUpper(trim(line.substr(0, colonPos)));
        line = trim(line.substr(colonPos + 1));
    }

    if (line.empty()) return al;

    // Split into tokens
    std::istringstream iss(line);
    std::string token;
    std::vector<std::string> tokens;
    // First token is the mnemonic
    iss >> token;
    al.mnemonic = toUpper(token);

    // Rest is operands (may contain commas)
    std::string rest;
    std::getline(iss, rest);
    rest = trim(rest);

    // Split by comma
    if (!rest.empty()) {
        size_t commaPos = rest.find(',');
        if (commaPos != std::string::npos) {
            al.operand1 = toUpper(trim(rest.substr(0, commaPos)));
            al.operand2 = toUpper(trim(rest.substr(commaPos + 1)));
        } else {
            al.operand1 = toUpper(trim(rest));
        }
    }

    // Handle data directives
    if (al.mnemonic == "DB" || al.mnemonic == "DW") {
        al.isData = true;
        al.dataDirective = al.mnemonic;
        // Parse comma-separated values from operand1 (and possibly more)
        std::string dataStr = rest;
        std::istringstream dss(dataStr);
        std::string part;
        while (std::getline(dss, part, ',')) {
            part = trim(part);
            int v = 0;
            if (isImmediate(part, v)) {
                al.dataValues.push_back(v);
            } else {
                // Could be a string in quotes
                if (part.size() >= 2 && part.front() == '"' && part.back() == '"') {
                    for (size_t i = 1; i < part.size() - 1; ++i) {
                        al.dataValues.push_back(static_cast<uint8_t>(part[i]));
                    }
                } else if (part.size() >= 2 && part.front() == '\'' && part.back() == '\'') {
                    for (size_t i = 1; i < part.size() - 1; ++i) {
                        al.dataValues.push_back(static_cast<uint8_t>(part[i]));
                    }
                } else {
                    al.dataValues.push_back(-1); // sentinel for unresolved symbol
                }
            }
        }
        al.size = static_cast<int>(al.dataValues.size()) *
                  (al.dataDirective == "DW" ? 2 : 1);
    }

    return al;
}

// ---------------------------------------------------------------------------
// Assembler class
// ---------------------------------------------------------------------------

class Assembler {
public:
    Assembler() : errorCount(0) {}

    bool assemble(const std::string &inputFile, const std::string &outputFile);

private:
    std::vector<AssemblyLine> lines;
    std::map<std::string, Symbol> symbolTable;
    std::vector<AssembledByte> objectCode;
    int errorCount;

    void error(int lineNumber, const std::string &msg);
    bool firstPass();
    bool secondPass();
    int instrSize(const AssemblyLine &al);
    bool encodeInstruction(const AssemblyLine &al);
    void writeListing(const std::string &filename);
    void emitByte(uint8_t b, int addr);
};

void Assembler::error(int lineNumber, const std::string &msg) {
    std::cerr << "Error at line " << lineNumber << ": " << msg << "\n";
    ++errorCount;
}

// Determine instruction size without resolving labels
int Assembler::instrSize(const AssemblyLine &al) {
    if (al.isData) return al.size;
    if (al.mnemonic.empty()) return 0;

    auto it = INSTR_TABLE.find(al.mnemonic);
    if (it == INSTR_TABLE.end()) return 0;

    const auto &defs = it->second;
    // Choose variant based on operands
    for (const auto &def : defs) {
        switch (def.operandType) {
        case OpType::NONE:
            if (al.operand1.empty()) return def.size;
            break;
        case OpType::REG:
            if (!al.operand1.empty() && al.operand2.empty() && isRegister(al.operand1))
                return def.size;
            break;
        case OpType::IMM: {
            int v;
            if (!al.operand1.empty() && al.operand2.empty() && isImmediate(al.operand1, v))
                return def.size;
            break;
        }
        case OpType::REG_REG:
            if (isRegister(al.operand1) && isRegister(al.operand2))
                return def.size;
            break;
        case OpType::REG_IMM: {
            int v;
            if (isRegister(al.operand1) && isImmediate(al.operand2, v))
                return def.size;
            break;
        }
        case OpType::LABEL:
            if (!al.operand1.empty()) return def.size;
            break;
        }
    }
    // Unknown/error – will be caught in second pass
    return 0;
}

// ---------------------------------------------------------------------------
// First pass: assign addresses, build symbol table
// ---------------------------------------------------------------------------
bool Assembler::firstPass() {
    int address = 0;
    for (auto &al : lines) {
        al.address = address;

        // Register label
        if (!al.label.empty()) {
            if (symbolTable.count(al.label)) {
                error(al.lineNumber,
                      "duplicate label '" + al.label + "'");
            } else {
                symbolTable[al.label] = {address, al.lineNumber};
            }
        }

        al.size = instrSize(al);

        // For instructions with unknown operands that might be labels (PUSH, etc.)
        // assume a tentative size
        if (al.size == 0 && !al.mnemonic.empty()) {
            auto it = INSTR_TABLE.find(al.mnemonic);
            if (it != INSTR_TABLE.end()) {
                // Take the largest variant size as fallback
                for (const auto &def : it->second) {
                    if (def.size > al.size) al.size = def.size;
                }
            }
        }

        address += al.size;
    }
    return errorCount == 0;
}

// ---------------------------------------------------------------------------
// Second pass: emit machine code
// ---------------------------------------------------------------------------
bool Assembler::encodeInstruction(const AssemblyLine &al) {
    if (al.mnemonic.empty()) return true;

    auto it = INSTR_TABLE.find(al.mnemonic);
    if (it == INSTR_TABLE.end()) {
        error(al.lineNumber, "unknown mnemonic '" + al.mnemonic + "'");
        return false;
    }

    const auto &defs = it->second;

    // Try each variant
    for (const auto &def : defs) {
        switch (def.operandType) {
        case OpType::NONE:
            if (al.operand1.empty()) {
                emitByte(def.opcode, al.address);
                return true;
            }
            break;

        case OpType::REG:
            if (!al.operand1.empty() && al.operand2.empty() &&
                isRegister(al.operand1)) {
                emitByte(def.opcode, al.address);
                emitByte(REG_TABLE.at(toUpper(al.operand1)),
                         al.address + 1);
                return true;
            }
            break;

        case OpType::IMM: {
            int v;
            if (!al.operand1.empty() && al.operand2.empty() &&
                isImmediate(al.operand1, v)) {
                emitByte(def.opcode, al.address);
                emitByte(static_cast<uint8_t>(v & 0xFF),
                         al.address + 1);
                emitByte(static_cast<uint8_t>((v >> 8) & 0xFF),
                         al.address + 2);
                return true;
            }
            break;
        }

        case OpType::REG_REG:
            if (isRegister(al.operand1) && isRegister(al.operand2)) {
                emitByte(def.opcode, al.address);
                emitByte(REG_TABLE.at(toUpper(al.operand1)),
                         al.address + 1);
                emitByte(REG_TABLE.at(toUpper(al.operand2)),
                         al.address + 2);
                return true;
            }
            break;

        case OpType::REG_IMM: {
            int v;
            if (isRegister(al.operand1) && isImmediate(al.operand2, v)) {
                emitByte(def.opcode, al.address);
                emitByte(REG_TABLE.at(toUpper(al.operand1)),
                         al.address + 1);
                emitByte(static_cast<uint8_t>(v & 0xFF),
                         al.address + 2);
                emitByte(static_cast<uint8_t>((v >> 8) & 0xFF),
                         al.address + 3);
                return true;
            }
            break;
        }

        case OpType::LABEL: {
            if (!al.operand1.empty()) {
                int targetAddr = 0;
                auto sym = symbolTable.find(al.operand1);
                if (sym == symbolTable.end()) {
                    error(al.lineNumber,
                          "undefined label '" + al.operand1 + "'");
                    return false;
                }
                targetAddr = sym->second.address;
                emitByte(def.opcode, al.address);
                emitByte(static_cast<uint8_t>(targetAddr & 0xFF),
                         al.address + 1);
                emitByte(static_cast<uint8_t>((targetAddr >> 8) & 0xFF),
                         al.address + 2);
                return true;
            }
            break;
        }
        }
    }

    // Try to handle PUSH with a label/symbol operand as address
    if (!al.operand1.empty()) {
        auto sym = symbolTable.find(al.operand1);
        if (sym != symbolTable.end()) {
            // Treat as IMM variant
            for (const auto &def : defs) {
                if (def.operandType == OpType::LABEL ||
                    def.operandType == OpType::IMM) {
                    int targetAddr = sym->second.address;
                    emitByte(def.opcode, al.address);
                    emitByte(static_cast<uint8_t>(targetAddr & 0xFF),
                             al.address + 1);
                    emitByte(
                        static_cast<uint8_t>((targetAddr >> 8) & 0xFF),
                        al.address + 2);
                    return true;
                }
            }
        }
    }

    error(al.lineNumber,
          "invalid operands for '" + al.mnemonic + "'");
    return false;
}

void Assembler::emitByte(uint8_t b, int addr) {
    objectCode.push_back({addr, b});
}

bool Assembler::secondPass() {
    for (const auto &al : lines) {
        if (al.mnemonic.empty() && al.label.empty()) continue;

        if (al.isData) {
            int off = 0;
            for (int v : al.dataValues) {
                if (al.dataDirective == "DB") {
                    emitByte(static_cast<uint8_t>(v & 0xFF),
                             al.address + off);
                    off += 1;
                } else { // DW
                    emitByte(static_cast<uint8_t>(v & 0xFF),
                             al.address + off);
                    emitByte(static_cast<uint8_t>((v >> 8) & 0xFF),
                             al.address + off + 1);
                    off += 2;
                }
            }
            continue;
        }

        if (!al.mnemonic.empty()) {
            encodeInstruction(al);
        }
    }
    return errorCount == 0;
}

// ---------------------------------------------------------------------------
// Write listing file
// ---------------------------------------------------------------------------
void Assembler::writeListing(const std::string &filename) {
    std::ofstream out(filename);
    if (!out) {
        std::cerr << "Cannot open output file: " << filename << "\n";
        return;
    }

    out << "Two-Pass Assembler - Listing File\n";
    out << "==================================\n\n";

    // Build address -> single byte map for display
    std::map<int, uint8_t> addrByte;
    for (const auto &b : objectCode) {
        addrByte[b.address] = b.value;
    }

    out << std::left << std::setw(6) << "LINE"
        << std::setw(6) << "ADDR"
        << std::setw(16) << "HEX"
        << "SOURCE\n";
    out << std::string(70, '-') << "\n";

    for (const auto &al : lines) {
        out << std::left << std::setw(6) << al.lineNumber;

        if (!al.mnemonic.empty() || !al.label.empty()) {
            out << std::right << std::hex << std::uppercase
                << std::setfill('0') << std::setw(4) << al.address
                << std::setfill(' ') << "  ";

            // Hex bytes
            std::ostringstream hexStr;
            for (int i = 0; i < al.size; ++i) {
                auto it = addrByte.find(al.address + i);
                if (it != addrByte.end()) {
                    hexStr << std::hex << std::uppercase
                           << std::setfill('0') << std::setw(2)
                           << static_cast<int>(it->second) << " ";
                }
            }
            out << std::left << std::setw(14) << hexStr.str();
        } else {
            out << std::string(22, ' ');
        }

        out << std::dec << al.raw << "\n";
    }

    out << "\n" << std::string(70, '-') << "\n";
    out << "Symbol Table:\n";
    out << std::string(30, '-') << "\n";
    out << std::left << std::setw(20) << "LABEL"
        << std::setw(8) << "ADDRESS" << "LINE\n";
    for (const auto &sym : symbolTable) {
        out << std::left << std::setfill(' ') << std::setw(20) << sym.first
            << std::right << std::hex << std::uppercase
            << std::setfill('0') << std::setw(4) << sym.second.address
            << "    " << std::setfill(' ') << std::dec << sym.second.lineNumber
            << "\n";
    }

    out << "\n";
    if (errorCount == 0) {
        out << "Assembly successful. "
            << objectCode.size() << " bytes generated.\n";
    } else {
        out << "Assembly failed with " << errorCount << " error(s).\n";
    }

    std::cout << "Listing written to: " << filename << "\n";
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------
bool Assembler::assemble(const std::string &inputFile,
                         const std::string &outputFile) {
    // Read source
    std::ifstream in(inputFile);
    if (!in) {
        std::cerr << "Cannot open input file: " << inputFile << "\n";
        return false;
    }

    std::string line;
    int lineNumber = 0;
    while (std::getline(in, line)) {
        ++lineNumber;
        lines.push_back(parseLine(line, lineNumber));
    }

    std::cout << "Assembling: " << inputFile << "\n";
    std::cout << "Pass 1...\n";
    firstPass();

    std::cout << "Pass 2...\n";
    secondPass();

    writeListing(outputFile);

    if (errorCount == 0) {
        std::cout << "Done. " << objectCode.size()
                  << " bytes of object code generated.\n";

        // Print symbol table summary
        std::cout << "\nSymbol Table (" << symbolTable.size() << " symbols):\n";
        for (const auto &sym : symbolTable) {
            std::cout << "  " << std::left << std::setfill(' ')
                      << std::setw(20) << sym.first
                      << "0x" << std::right << std::hex << std::uppercase
                      << std::setfill('0') << std::setw(4)
                      << sym.second.address << "\n";
        }

        // Print object code hex dump
        std::cout << "\nObject Code:\n";
        int col = 0;
        for (const auto &b : objectCode) {
            if (col == 0) {
                std::cout << "  " << std::hex << std::uppercase
                          << std::setfill('0') << std::setw(4) << b.address
                          << ": ";
            }
            std::cout << std::hex << std::uppercase
                      << std::setfill('0') << std::setw(2)
                      << static_cast<int>(b.value) << " ";
            ++col;
            if (col == 16) {
                std::cout << "\n";
                col = 0;
            }
        }
        if (col != 0) std::cout << "\n";
    } else {
        std::cerr << errorCount << " error(s) found.\n";
    }

    return errorCount == 0;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char *argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0]
                  << " <input.asm> [output.lst]\n";
        return 1;
    }

    std::string inputFile = argv[1];
    std::string outputFile = (argc >= 3) ? argv[2]
                                         : inputFile + ".lst";

    Assembler asm_;
    bool ok = asm_.assemble(inputFile, outputFile);
    return ok ? 0 : 1;
}

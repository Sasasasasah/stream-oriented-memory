#ifndef MEM_MODEL_H
#define MEM_MODEL_H

#include <cstddef>
#include <cstdint>
#include <vector>

class MemBankSuperlaneLeafModel {
public:
    static constexpr std::size_t P_MEM_BANK_DEPTH_ROWS = 32768;
    static constexpr std::size_t P_LANES_PER_TILE = 8;
    static constexpr std::size_t P_MEM_ELEMENT_BITS = 8;
    static constexpr std::size_t P_MEM_READ_TO_SR_CYCLES = 1;

    static constexpr std::uint8_t OPCODE_READ = 0x0;
    static constexpr std::uint8_t OPCODE_WRITE = 0x1;

    enum class FaultCode : std::uint8_t {
        NONE = 0,
        ILLEGAL_OPCODE = 1,
        READ_PRESERVE = 2,
        INVALID_WRITE = 3
    };

    struct Inputs {
        bool cmd_valid = false;
        std::uint8_t cmd_opcode = OPCODE_READ;
        std::uint16_t cmd_row = 0;
        bool cmd_stream_dir = false;
        std::uint8_t cmd_stream_idx = 0;
        bool cmd_preserve = false;
        bool stream_valid = false;
        std::uint64_t stream_data = 0;
    };

    struct Outputs {
        bool stream_consume = false;
        bool read_valid = false;
        std::uint64_t read_data = 0;
        bool read_stream_dir = false;
        std::uint8_t read_stream_idx = 0;
        bool fault_valid = false;
        FaultCode fault_code = FaultCode::NONE;
    };

    explicit MemBankSuperlaneLeafModel(
        std::size_t depth_rows = P_MEM_BANK_DEPTH_ROWS);

    void reset();
    Outputs step(const Inputs& inputs);
    const Outputs& outputs() const;
    std::size_t depth_rows() const;

private:
    std::vector<std::uint64_t> storage_;
    Outputs outputs_;
};

#endif

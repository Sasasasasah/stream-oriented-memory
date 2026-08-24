#ifndef MEM_LOGICAL_BANK_MODEL_H
#define MEM_LOGICAL_BANK_MODEL_H

#include "mem_model.h"

#include <array>
#include <cstddef>
#include <cstdint>

class MemLogicalBankModel {
public:
    static constexpr std::size_t TILE_ROWS = 4;

    struct CommandView {
        bool valid = false;
        std::uint32_t raw = 0;
        std::uint8_t opcode = 0;
        std::uint16_t row = 0;
        bool stream_dir = false;
        std::uint8_t stream_idx = 0;
        bool preserve = false;
    };

    struct Inputs {
        bool cmd_valid = false;
        std::uint32_t cmd_raw = 0;
        std::array<bool, TILE_ROWS> stream_valid{};
        std::array<std::uint64_t, TILE_ROWS> stream_data{};
    };

    struct Outputs {
        std::array<MemBankSuperlaneLeafModel::Outputs, TILE_ROWS> tile{};
        bool pipeline_busy = false;
        bool north_cmd_valid = false;
        std::uint32_t north_cmd = 0;
    };

    explicit MemLogicalBankModel(
        std::size_t depth_rows =
            MemBankSuperlaneLeafModel::P_MEM_BANK_DEPTH_ROWS);

    void reset();
    std::array<CommandView, TILE_ROWS> current_commands(
        bool south_valid, std::uint32_t south_raw) const;
    Outputs step(const Inputs& inputs);
    std::uint64_t cycle() const;

private:
    static MemBankSuperlaneLeafModel::Inputs decode_leaf_input(
        const CommandView& command,
        bool stream_valid,
        std::uint64_t stream_data);

    std::array<MemBankSuperlaneLeafModel, TILE_ROWS> leaves_;
    std::array<bool, TILE_ROWS - 1> stage_valid_{};
    std::array<std::uint32_t, TILE_ROWS - 1> stage_command_{};
    std::uint64_t cycle_ = 0;
};

#endif

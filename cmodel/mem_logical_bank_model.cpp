#include "mem_logical_bank_model.h"

MemLogicalBankModel::MemLogicalBankModel(const std::size_t depth_rows)
    : leaves_{MemBankSuperlaneLeafModel(depth_rows),
              MemBankSuperlaneLeafModel(depth_rows),
              MemBankSuperlaneLeafModel(depth_rows),
              MemBankSuperlaneLeafModel(depth_rows)} {
    reset();
}

void MemLogicalBankModel::reset() {
    for (auto& leaf : leaves_) {
        leaf.reset();
    }
    stage_valid_.fill(false);
    stage_command_.fill(0);
    cycle_ = 0;
}

MemBankSuperlaneLeafModel::Inputs MemLogicalBankModel::decode_leaf_input(
    const CommandView& command,
    const bool stream_valid,
    const std::uint64_t stream_data) {
    MemBankSuperlaneLeafModel::Inputs input{};
    input.cmd_valid = command.valid;
    input.cmd_opcode = command.opcode;
    input.cmd_stream_idx = command.stream_idx;
    input.cmd_stream_dir = command.stream_dir;
    input.cmd_row = command.row;
    input.cmd_preserve = command.preserve;
    input.stream_valid = stream_valid;
    input.stream_data = stream_data;
    return input;
}

std::array<MemLogicalBankModel::CommandView,
           MemLogicalBankModel::TILE_ROWS>
MemLogicalBankModel::current_commands(const bool south_valid,
                                      const std::uint32_t south_raw) const {
    std::array<CommandView, TILE_ROWS> commands{};
    commands[0].valid = south_valid;
    commands[0].raw = south_raw;
    for (std::size_t tile = 1; tile < TILE_ROWS; ++tile) {
        commands[tile].valid = stage_valid_[tile - 1];
        commands[tile].raw = stage_command_[tile - 1];
    }
    for (auto& command : commands) {
        command.opcode = static_cast<std::uint8_t>(command.raw & 0x7U);
        command.stream_idx =
            static_cast<std::uint8_t>((command.raw >> 3U) & 0x1FU);
        command.stream_dir = ((command.raw >> 8U) & 0x1U) != 0U;
        command.row = static_cast<std::uint16_t>(
            (command.raw >> 15U) & 0x7FFFU);
        command.preserve = ((command.raw >> 31U) & 0x1U) != 0U;
    }
    return commands;
}

MemLogicalBankModel::Outputs MemLogicalBankModel::step(
    const Inputs& inputs) {
    Outputs outputs{};
    const auto active_command =
        current_commands(inputs.cmd_valid, inputs.cmd_raw);

    // The RTL registers the tile3 command at the cycle edge. step() returns
    // the post-edge observable outputs, so the current tile3 view is north.
    outputs.north_cmd_valid = active_command[TILE_ROWS - 1].valid;
    outputs.north_cmd = active_command[TILE_ROWS - 1].raw;

    // Execute all active leaves before changing control-pipeline state. Four
    // leaves are independent single-port memories and may execute together.
    for (std::size_t tile = 0; tile < TILE_ROWS; ++tile) {
        outputs.pipeline_busy =
            outputs.pipeline_busy || active_command[tile].valid;
        outputs.tile[tile] = leaves_[tile].step(decode_leaf_input(
            active_command[tile],
            inputs.stream_valid[tile], inputs.stream_data[tile]));
    }

    // Cycle commit after all active leaves execute.
    for (std::size_t stage = TILE_ROWS - 2; stage > 0; --stage) {
        stage_valid_[stage] = stage_valid_[stage - 1];
        stage_command_[stage] = stage_command_[stage - 1];
    }
    stage_valid_[0] = inputs.cmd_valid;
    stage_command_[0] = inputs.cmd_raw;

    ++cycle_;
    return outputs;
}

std::uint64_t MemLogicalBankModel::cycle() const {
    return cycle_;
}

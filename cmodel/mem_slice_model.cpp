#include "mem_slice_model.h"

MemSliceModel::MemSliceModel(const std::size_t depth_rows)
    : banks_{MemLogicalBankModel(depth_rows),
             MemLogicalBankModel(depth_rows)} {
    reset();
}

void MemSliceModel::reset() {
    for (auto& bank : banks_) {
        bank.reset();
    }
    cycle_ = 0;
}

bool MemSliceModel::issue_is_legal(const std::uint32_t raw_command) {
    const auto opcode = static_cast<std::uint8_t>(raw_command & 0x7U);
    const bool supported_opcode = opcode == 0U || opcode == 1U;
    const bool read_preserve =
        opcode == 0U && ((raw_command >> 31U) & 0x1U) != 0U;
    const bool map_stream_nonzero =
        ((raw_command >> 9U) & 0x3FU) != 0U;
    const bool reserved = ((raw_command >> 30U) & 0x1U) != 0U;
    return supported_opcode && !read_preserve &&
           !map_stream_nonzero && !reserved;
}

MemSliceModel::Outputs MemSliceModel::step(const Inputs& inputs) {
    Outputs outputs{};
    std::array<bool, BANKS> issue_legal{};
    std::array<MemLogicalBankModel::Inputs, BANKS> bank_inputs{};
    std::array<std::array<MemLogicalBankModel::CommandView, TILES>, BANKS>
        current_command{};

    // Both banks observe the same immutable cycle-start SR state. Calling one
    // bank first cannot expose its next-state to the other bank.
    for (std::size_t bank = 0; bank < BANKS; ++bank) {
        issue_legal[bank] = issue_is_legal(inputs.bank_issue_raw[bank]);
        bank_inputs[bank].cmd_valid =
            inputs.bank_issue_valid[bank] && issue_legal[bank];
        bank_inputs[bank].cmd_raw = inputs.bank_issue_raw[bank];
        current_command[bank] = banks_[bank].current_commands(
            bank_inputs[bank].cmd_valid, bank_inputs[bank].cmd_raw);

        for (std::size_t tile = 0; tile < TILES; ++tile) {
            const auto& command = current_command[bank][tile];
            const std::size_t direction = command.stream_dir ? 1U : 0U;
            const std::size_t stream = command.stream_idx;
            bank_inputs[bank].stream_valid[tile] =
                inputs.sr_state[direction][stream][tile].valid;
            bank_inputs[bank].stream_data[tile] =
                inputs.sr_state[direction][stream][tile].data;
        }
    }

    std::array<MemLogicalBankModel::Outputs, BANKS> bank_outputs{};
    for (std::size_t bank = 0; bank < BANKS; ++bank) {
        bank_outputs[bank] = banks_[bank].step(bank_inputs[bank]);
        outputs.bank_busy[bank] = bank_outputs[bank].pipeline_busy;
        outputs.slice_busy = outputs.slice_busy || outputs.bank_busy[bank];
        outputs.north_cmd_valid[bank] =
            bank_outputs[bank].north_cmd_valid;
        outputs.north_cmd[bank] = bank_outputs[bank].north_cmd;

        for (std::size_t tile = 0; tile < TILES; ++tile) {
            const auto& leaf = bank_outputs[bank].tile[tile];
            const auto& command = current_command[bank][tile];
            if (leaf.stream_consume) {
                const std::size_t direction = command.stream_dir ? 1U : 0U;
                outputs.consume[bank][direction][command.stream_idx][tile] =
                    true;
            }
            outputs.injection[bank][tile].valid = leaf.read_valid;
            outputs.injection[bank][tile].data = leaf.read_data;
            outputs.injection[bank][tile].stream_dir =
                leaf.read_stream_dir;
            outputs.injection[bank][tile].stream_idx =
                leaf.read_stream_idx;
            outputs.injection[bank][tile].row = command.row;
        }
    }

    // Per-bank aggregate fault. Metadata priority matches mem_slice.v and is
    // diagnostic only: issue, lowest-tile collision, lowest-tile leaf fault.
    for (std::size_t bank = 0; bank < BANKS; ++bank) {
        auto& fault = outputs.fault[bank];
        fault.bank_id = static_cast<std::uint8_t>(bank);
        if (inputs.bank_issue_valid[bank] && !issue_legal[bank]) {
            fault.valid = true;
            fault.code = FaultCode::ISSUE;
            fault.row = static_cast<std::uint16_t>(
                (inputs.bank_issue_raw[bank] >> 15U) & 0x7FFFU);
        }

        for (std::size_t tile = 0; tile < TILES && !fault.valid; ++tile) {
            if (bank_outputs[bank].tile[tile].fault_valid) {
                fault.valid = true;
                fault.code = FaultCode::LEAF;
                fault.tile_valid = true;
                fault.tile_id = static_cast<std::uint8_t>(tile);
                fault.row = current_command[bank][tile].row;
            }
        }
    }

    apply_collision_feedback(inputs.producer_collision, outputs);

    ++cycle_;
    return outputs;
}

void MemSliceModel::apply_collision_feedback(
    const CollisionFeedback& collision, Outputs& outputs) const {
    for (std::size_t bank = 0; bank < BANKS; ++bank) {
        auto& fault = outputs.fault[bank];
        if (fault.valid && fault.code == FaultCode::ISSUE) {
            continue;
        }
        for (std::size_t tile = 0; tile < TILES; ++tile) {
            if (outputs.injection[bank][tile].valid &&
                collision[bank][tile]) {
                fault.valid = true;
                fault.code = FaultCode::COLLISION;
                fault.tile_valid = true;
                fault.tile_id = static_cast<std::uint8_t>(tile);
                fault.row = outputs.injection[bank][tile].row;
                break;
            }
        }
    }
}

std::uint64_t MemSliceModel::cycle() const {
    return cycle_;
}

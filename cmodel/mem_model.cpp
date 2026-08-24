#include "mem_model.h"

MemBankSuperlaneLeafModel::MemBankSuperlaneLeafModel(
    const std::size_t depth_rows)
    : storage_(depth_rows), outputs_{} {}

void MemBankSuperlaneLeafModel::reset() {
    // Reset affects only observable control state. The storage vector is not
    // modified, matching the RTL rule that SRAM contents are not reset.
    outputs_ = Outputs{};
}

MemBankSuperlaneLeafModel::Outputs MemBankSuperlaneLeafModel::step(
    const Inputs& inputs) {
    // Pulse outputs return to zero at the start of every modeled cycle.
    outputs_.stream_consume = false;
    outputs_.read_valid = false;
    outputs_.fault_valid = false;
    outputs_.fault_code = FaultCode::NONE;

    if (!inputs.cmd_valid) {
        return outputs_;
    }

    switch (inputs.cmd_opcode) {
    case OPCODE_READ:
        if (inputs.cmd_preserve) {
            outputs_.fault_valid = true;
            outputs_.fault_code = FaultCode::READ_PRESERVE;
            return outputs_;
        }

        outputs_.read_data = storage_.at(inputs.cmd_row);
        outputs_.read_stream_dir = inputs.cmd_stream_dir;
        outputs_.read_stream_idx =
            static_cast<std::uint8_t>(inputs.cmd_stream_idx & 0x1FU);
        outputs_.read_valid = true;
        return outputs_;

    case OPCODE_WRITE:
        if (inputs.cmd_preserve) {
            // WriteTap with invalid stream input is a no-op without a fault.
            if (inputs.stream_valid) {
                storage_.at(inputs.cmd_row) = inputs.stream_data;
            }
            return outputs_;
        }

        if (inputs.stream_valid) {
            storage_.at(inputs.cmd_row) = inputs.stream_data;
            outputs_.stream_consume = true;
        } else {
            outputs_.fault_valid = true;
            outputs_.fault_code = FaultCode::INVALID_WRITE;
        }
        return outputs_;

    default:
        outputs_.fault_valid = true;
        outputs_.fault_code = FaultCode::ILLEGAL_OPCODE;
        return outputs_;
    }
}

const MemBankSuperlaneLeafModel::Outputs&
MemBankSuperlaneLeafModel::outputs() const {
    return outputs_;
}

std::size_t MemBankSuperlaneLeafModel::depth_rows() const {
    return storage_.size();
}

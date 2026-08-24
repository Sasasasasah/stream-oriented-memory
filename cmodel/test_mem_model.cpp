#include "mem_model.h"

#include <cstdint>
#include <iostream>
#include <string>

namespace {

using Model = MemBankSuperlaneLeafModel;

int errors = 0;

void expect(const bool condition, const std::string& message) {
    if (!condition) {
        std::cout << "ERROR " << message << '\n';
        ++errors;
    }
}

Model::Inputs write_input(const std::uint16_t row,
                          const std::uint64_t data,
                          const bool preserve,
                          const bool stream_valid) {
    Model::Inputs input{};
    input.cmd_valid = true;
    input.cmd_opcode = Model::OPCODE_WRITE;
    input.cmd_row = row;
    input.cmd_preserve = preserve;
    input.stream_valid = stream_valid;
    input.stream_data = data;
    return input;
}

Model::Inputs read_input(const std::uint16_t row,
                         const bool direction,
                         const std::uint8_t stream_index,
                         const bool preserve = false) {
    Model::Inputs input{};
    input.cmd_valid = true;
    input.cmd_opcode = Model::OPCODE_READ;
    input.cmd_row = row;
    input.cmd_stream_dir = direction;
    input.cmd_stream_idx = stream_index;
    input.cmd_preserve = preserve;
    return input;
}

void expect_read(const Model::Outputs& output,
                 const std::uint64_t data,
                 const bool direction,
                 const std::uint8_t stream_index,
                 const std::string& name) {
    expect(output.read_valid, name + " read_valid");
    expect(!output.stream_consume, name + " no consume");
    expect(!output.fault_valid, name + " no fault");
    expect(output.read_data == data, name + " data");
    expect(output.read_stream_dir == direction, name + " direction");
    expect(output.read_stream_idx == stream_index, name + " stream index");
}

}  // namespace

int main() {
    Model model;

    std::cout << "RUN_TEST reset_control_outputs\n";
    model.reset();
    const auto reset_output = model.outputs();
    expect(!reset_output.stream_consume, "reset consume clear");
    expect(!reset_output.read_valid, "reset read clear");
    expect(!reset_output.fault_valid, "reset fault clear");
    expect(model.depth_rows() == Model::P_MEM_BANK_DEPTH_ROWS,
           "default depth");

    std::cout << "RUN_TEST valid_normal_write\n";
    auto output = model.step(
        write_input(10, UINT64_C(0x1122334455667788), false, true));
    expect(output.stream_consume, "normal write consume");
    expect(!output.read_valid, "normal write no read");
    expect(!output.fault_valid, "normal write no fault");

    std::cout << "RUN_TEST read\n";
    output = model.step(read_input(10, true, 17));
    expect_read(output, UINT64_C(0x1122334455667788), true, 17, "read");

    std::cout << "RUN_TEST read_after_write\n";
    output = model.step(
        write_input(20, UINT64_C(0xA5A55A5A12345678), false, true));
    expect(output.stream_consume, "RAW write consume");
    output = model.step(read_input(20, false, 9));
    expect_read(output, UINT64_C(0xA5A55A5A12345678), false, 9,
                "RAW read C plus 1");

    std::cout << "RUN_TEST invalid_normal_write\n";
    model.step(write_input(30, UINT64_C(0x0102030405060708), false, true));
    output = model.step(
        write_input(30, UINT64_C(0xDEADBEEFDEADBEEF), false, false));
    expect(!output.stream_consume, "invalid Write no consume");
    expect(!output.read_valid, "invalid Write no read");
    expect(output.fault_valid, "invalid Write fault");
    expect(output.fault_code == Model::FaultCode::INVALID_WRITE,
           "invalid Write fault code");
    output = model.step(read_input(30, false, 3));
    expect_read(output, UINT64_C(0x0102030405060708), false, 3,
                "invalid Write storage unchanged");

    std::cout << "RUN_TEST valid_writetap\n";
    output = model.step(
        write_input(40, UINT64_C(0xCAFEBABE89ABCDEF), true, true));
    expect(!output.stream_consume, "WriteTap no consume");
    expect(!output.read_valid, "WriteTap no read");
    expect(!output.fault_valid, "WriteTap no fault");
    output = model.step(read_input(40, true, 12));
    expect_read(output, UINT64_C(0xCAFEBABE89ABCDEF), true, 12,
                "WriteTap readback");

    std::cout << "RUN_TEST invalid_writetap\n";
    output = model.step(
        write_input(40, UINT64_C(0xFFFFFFFFFFFFFFFF), true, false));
    expect(!output.stream_consume, "invalid WriteTap no consume");
    expect(!output.read_valid, "invalid WriteTap no read");
    expect(!output.fault_valid, "invalid WriteTap no fault");
    output = model.step(read_input(40, false, 13));
    expect_read(output, UINT64_C(0xCAFEBABE89ABCDEF), false, 13,
                "invalid WriteTap storage unchanged");

    std::cout << "RUN_TEST unsupported_opcode\n";
    Model::Inputs illegal{};
    illegal.cmd_valid = true;
    illegal.cmd_opcode = 5;
    illegal.cmd_row = 40;
    illegal.stream_valid = true;
    illegal.stream_data = UINT64_C(0x0BAD0BAD0BAD0BAD);
    output = model.step(illegal);
    expect(!output.stream_consume, "illegal opcode no consume");
    expect(!output.read_valid, "illegal opcode no read");
    expect(output.fault_valid, "illegal opcode fault");
    expect(output.fault_code == Model::FaultCode::ILLEGAL_OPCODE,
           "illegal opcode fault code");
    output = model.step(read_input(40, false, 14));
    expect_read(output, UINT64_C(0xCAFEBABE89ABCDEF), false, 14,
                "illegal opcode storage unchanged");

    std::cout << "RUN_TEST read_preserve_illegal\n";
    output = model.step(read_input(40, true, 15, true));
    expect(!output.stream_consume, "Read preserve no consume");
    expect(!output.read_valid, "Read preserve no response");
    expect(output.fault_valid, "Read preserve fault");
    expect(output.fault_code == Model::FaultCode::READ_PRESERVE,
           "Read preserve fault code");

    std::cout << "RUN_TEST independent_rows\n";
    model.step(write_input(100, UINT64_C(0x1000100010001000), false, true));
    model.step(write_input(101, UINT64_C(0x2000200020002000), false, true));
    model.step(write_input(102, UINT64_C(0x3000300030003000), false, true));
    expect_read(model.step(read_input(100, false, 1)),
                UINT64_C(0x1000100010001000), false, 1, "row 100");
    expect_read(model.step(read_input(101, false, 2)),
                UINT64_C(0x2000200020002000), false, 2, "row 101");
    expect_read(model.step(read_input(102, false, 3)),
                UINT64_C(0x3000300030003000), false, 3, "row 102");

    std::cout << "RUN_TEST pulse_clear\n";
    output = model.step(Model::Inputs{});
    expect(!output.stream_consume, "idle consume clear");
    expect(!output.read_valid, "idle read clear");
    expect(!output.fault_valid, "idle fault clear");

    if (errors == 0) {
        std::cout << "CMODEL_TEST_PASS\n";
        return 0;
    }

    std::cout << "CMODEL_TEST_FAIL errors=" << errors << '\n';
    return 1;
}

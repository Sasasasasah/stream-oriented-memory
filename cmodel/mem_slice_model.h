#ifndef MEM_SLICE_MODEL_H
#define MEM_SLICE_MODEL_H

#include "mem_logical_bank_model.h"

#include <array>
#include <cstddef>
#include <cstdint>

class MemSliceModel {
public:
    static constexpr std::size_t BANKS = 2;
    static constexpr std::size_t DIRECTIONS = 2;
    static constexpr std::size_t STREAMS = 32;
    static constexpr std::size_t TILES = 4;

    enum class FaultCode : std::uint8_t {
        NONE = 0,
        ISSUE = 1,
        LEAF = 2,
        COLLISION = 3
    };

    struct SrCell {
        bool valid = false;
        std::uint64_t data = 0;
    };

    using SrTileState = std::array<SrCell, TILES>;
    using SrStreamState = std::array<SrTileState, STREAMS>;
    using SrState = std::array<SrStreamState, DIRECTIONS>;
    using ConsumeTileState = std::array<bool, TILES>;
    using ConsumeStreamState = std::array<ConsumeTileState, STREAMS>;
    using ConsumeDirectionState =
        std::array<ConsumeStreamState, DIRECTIONS>;
    using CollisionFeedback = std::array<std::array<bool, TILES>, BANKS>;

    struct Inputs {
        std::array<bool, BANKS> bank_issue_valid{};
        std::array<std::uint32_t, BANKS> bank_issue_raw{};
        SrState sr_state{};
        CollisionFeedback producer_collision{};
    };

    struct Injection {
        bool valid = false;
        std::uint64_t data = 0;
        bool stream_dir = false;
        std::uint8_t stream_idx = 0;
        std::uint16_t row = 0;
    };

    struct Fault {
        bool valid = false;
        FaultCode code = FaultCode::NONE;
        std::uint8_t bank_id = 0;
        bool tile_valid = false;
        std::uint8_t tile_id = 0;
        std::uint16_t row = 0;
    };

    struct Outputs {
        std::array<ConsumeDirectionState, BANKS> consume{};
        std::array<std::array<Injection, TILES>, BANKS> injection{};
        std::array<Fault, BANKS> fault{};
        std::array<bool, BANKS> bank_busy{};
        bool slice_busy = false;
        std::array<bool, BANKS> north_cmd_valid{};
        std::array<std::uint32_t, BANKS> north_cmd{};
    };

    explicit MemSliceModel(
        std::size_t depth_rows =
            MemBankSuperlaneLeafModel::P_MEM_BANK_DEPTH_ROWS);

    void reset();
    Outputs step(const Inputs& inputs);
    void apply_collision_feedback(const CollisionFeedback& collision,
                                  Outputs& outputs) const;
    std::uint64_t cycle() const;

private:
    static bool issue_is_legal(std::uint32_t raw_command);

    std::array<MemLogicalBankModel, BANKS> banks_;
    std::uint64_t cycle_ = 0;
};

#endif

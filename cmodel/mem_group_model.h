#ifndef MEM_GROUP_MODEL_H
#define MEM_GROUP_MODEL_H

#include "mem_slice_model.h"

#include <array>
#include <cstddef>
#include <cstdint>

class MemGroupModel {
public:
    static constexpr std::size_t SLICES = 4;
    static constexpr std::size_t BANKS = MemSliceModel::BANKS;
    static constexpr std::size_t TILES = MemSliceModel::TILES;

    using IssueValid = std::array<std::array<bool, BANKS>, SLICES>;
    using IssueRaw =
        std::array<std::array<std::uint32_t, BANKS>, SLICES>;
    using CollisionFeedback =
        std::array<MemSliceModel::CollisionFeedback, SLICES>;

    struct Inputs {
        IssueValid issue_valid{};
        IssueRaw issue_raw{};
        MemSliceModel::SrState left_boundary_state{};
        MemSliceModel::SrState right_boundary_state{};
        CollisionFeedback external_collision{};
    };

    struct Producer {
        bool valid = false;
        std::uint64_t data = 0;
        bool stream_dir = false;
        std::uint8_t stream_idx = 0;
    };

    using Producers =
        std::array<std::array<std::array<Producer, TILES>, BANKS>, SLICES>;

    struct Outputs {
        MemSliceModel::ConsumeDirectionState left_consume{};
        MemSliceModel::ConsumeDirectionState right_consume{};
        Producers left_producer{};
        Producers right_producer{};
        CollisionFeedback internal_collision{};
        std::array<MemSliceModel::Outputs, SLICES> slice{};
        std::array<bool, SLICES> slice_busy{};
        bool group_busy = false;
        bool group_fault_valid = false;
    };

    explicit MemGroupModel(
        std::size_t depth_rows =
            MemBankSuperlaneLeafModel::P_MEM_BANK_DEPTH_ROWS);

    void reset();
    Outputs step(const Inputs& inputs);
    void apply_collision_feedback(const CollisionFeedback& external,
                                  Outputs& outputs) const;
    std::uint64_t cycle() const;

private:
    std::array<MemSliceModel, SLICES> slices_;
    std::uint64_t cycle_ = 0;
};

#endif

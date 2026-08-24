#include "mem_group_model.h"

MemGroupModel::MemGroupModel(const std::size_t depth_rows)
    : slices_{MemSliceModel(depth_rows), MemSliceModel(depth_rows),
              MemSliceModel(depth_rows), MemSliceModel(depth_rows)} {
    reset();
}

void MemGroupModel::reset() {
    for (auto& slice : slices_) {
        slice.reset();
    }
    cycle_ = 0;
}

MemGroupModel::Outputs MemGroupModel::step(const Inputs& inputs) {
    Outputs outputs{};
    std::array<MemSliceModel::Inputs, SLICES> slice_inputs{};

    // Snapshot-derived Slice inputs: East observes left, West observes right.
    // All four Slice models receive values from the same immutable group input.
    for (std::size_t slice = 0; slice < SLICES; ++slice) {
        slice_inputs[slice].bank_issue_valid = inputs.issue_valid[slice];
        slice_inputs[slice].bank_issue_raw = inputs.issue_raw[slice];
        for (std::size_t stream = 0; stream < MemSliceModel::STREAMS;
             ++stream) {
            for (std::size_t tile = 0; tile < TILES; ++tile) {
                slice_inputs[slice].sr_state[0][stream][tile] =
                    inputs.left_boundary_state[0][stream][tile];
                slice_inputs[slice].sr_state[1][stream][tile] =
                    inputs.right_boundary_state[1][stream][tile];
            }
        }
        // Intra-group collisions are unknown until every Slice has stepped.
        slice_inputs[slice].producer_collision = {};
    }

    for (std::size_t slice = 0; slice < SLICES; ++slice) {
        outputs.slice[slice] = slices_[slice].step(slice_inputs[slice]);
        outputs.slice_busy[slice] = outputs.slice[slice].slice_busy;
        outputs.group_busy = outputs.group_busy || outputs.slice_busy[slice];

        for (std::size_t bank = 0; bank < BANKS; ++bank) {
            for (std::size_t direction = 0;
                 direction < MemSliceModel::DIRECTIONS; ++direction) {
                for (std::size_t stream = 0;
                     stream < MemSliceModel::STREAMS; ++stream) {
                    for (std::size_t tile = 0; tile < TILES; ++tile) {
                        if (outputs.slice[slice]
                                .consume[bank][direction][stream][tile]) {
                            if (direction == 0U) {
                                outputs.left_consume[direction][stream][tile] =
                                    true;
                            } else {
                                outputs.right_consume[direction][stream][tile] =
                                    true;
                            }
                        }
                    }
                }
            }

            for (std::size_t tile = 0; tile < TILES; ++tile) {
                const auto& injection =
                    outputs.slice[slice].injection[bank][tile];
                auto& producer = injection.stream_dir
                    ? outputs.left_producer[slice][bank][tile]
                    : outputs.right_producer[slice][bank][tile];
                producer.valid = injection.valid;
                producer.data = injection.data;
                producer.stream_dir = injection.stream_dir;
                producer.stream_idx = injection.stream_idx;
            }
        }
    }

    // Intra-group comparison preserves all producer candidates. Target
    // equality is direction/boundary, stream, and tile; there is no winner.
    for (std::size_t slice_a = 0; slice_a < SLICES; ++slice_a) {
        for (std::size_t bank_a = 0; bank_a < BANKS; ++bank_a) {
            for (std::size_t tile_a = 0; tile_a < TILES; ++tile_a) {
                const auto& producer_a =
                    outputs.slice[slice_a].injection[bank_a][tile_a];
                if (!producer_a.valid) {
                    continue;
                }
                for (std::size_t slice_b = 0; slice_b < SLICES; ++slice_b) {
                    for (std::size_t bank_b = 0; bank_b < BANKS; ++bank_b) {
                        for (std::size_t tile_b = 0; tile_b < TILES; ++tile_b) {
                            if (slice_a == slice_b && bank_a == bank_b &&
                                tile_a == tile_b) {
                                continue;
                            }
                            const auto& producer_b = outputs.slice[slice_b]
                                .injection[bank_b][tile_b];
                            if (producer_b.valid && tile_a == tile_b &&
                                producer_a.stream_dir ==
                                    producer_b.stream_dir &&
                                producer_a.stream_idx ==
                                    producer_b.stream_idx) {
                                outputs.internal_collision
                                    [slice_a][bank_a][tile_a] = true;
                            }
                        }
                    }
                }
            }
        }
    }

    apply_collision_feedback(inputs.external_collision, outputs);

    ++cycle_;
    return outputs;
}

void MemGroupModel::apply_collision_feedback(
    const CollisionFeedback& external, Outputs& outputs) const {
    // Re-evaluate diagnostic feedback without stepping a Slice twice. This
    // lets a Hemisphere first discover each producer's physical boundary and
    // then route boundary-local collision feedback to the owning Slice.
    outputs.group_fault_valid = false;
    for (std::size_t slice = 0; slice < SLICES; ++slice) {
        MemSliceModel::CollisionFeedback combined{};
        for (std::size_t bank = 0; bank < BANKS; ++bank) {
            for (std::size_t tile = 0; tile < TILES; ++tile) {
                combined[bank][tile] =
                    outputs.internal_collision[slice][bank][tile] ||
                    external[slice][bank][tile];
            }
        }
        slices_[slice].apply_collision_feedback(combined,
                                                outputs.slice[slice]);
        for (const auto& fault : outputs.slice[slice].fault) {
            outputs.group_fault_valid =
                outputs.group_fault_valid || fault.valid;
        }
    }
}

std::uint64_t MemGroupModel::cycle() const {
    return cycle_;
}

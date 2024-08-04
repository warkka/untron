fn combine_hashes(left: &[u8], right: &[u8]) -> [u8; 32] {
    let mut combined = Vec::with_capacity(64);
    combined.extend_from_slice(left);
    combined.extend_from_slice(right);
    zktron::hash(&combined)
}

pub fn create_merkle_tree(leaves: &[[u8; 32]]) -> [u8; 32] {
    if leaves.is_empty() {
        return [0u8; 32];
    }

    let mut current_level = leaves.to_vec();

    while current_level.len() > 1 {
        let mut next_level = Vec::new();

        for chunk in current_level.chunks(2) {
            if chunk.len() == 2 {
                next_level.push(combine_hashes(&chunk[0], &chunk[1]));
            } else {
                next_level.push(chunk[0]);
            }
        }

        current_level = next_level;
    }

    current_level[0]
}

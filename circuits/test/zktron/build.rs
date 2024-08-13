use sp1_helper::build_program;
use std::path::Path;
use std::io;
use std::fs;

fn copy_dir_all(src: impl AsRef<Path>, dst: impl AsRef<Path>) -> io::Result<()> {
    fs::create_dir_all(&dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(entry.path(), dst.as_ref().join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.as_ref().join(entry.file_name()))?;
        }
    }
    Ok(())
}


fn main() -> Result<(), Box<dyn std::error::Error>> {
    build_program("../../zktron");

    copy_dir_all(
        Path::new("../../googleapis/google"),
        Path::new("../../java-tron/protocol/src/main/protos/google"),
    )?;
    tonic_build::configure()
        .build_server(false)
        .boxed("BlockExtention")
        .compile(
            &["../../java-tron/protocol/src/main/protos/api/api.proto"],
            &["../../java-tron/protocol/src/main/protos"],
        )?;
    fs::remove_dir_all("../../java-tron/protocol/src/main/protos/google")?;
    Ok(())
}

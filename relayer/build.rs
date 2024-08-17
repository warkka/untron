use std::fs;
use std::io;
use std::path::Path;

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
    copy_dir_all(
        Path::new("../lib/googleapis/google"),
        Path::new("../lib/java-tron/protocol/src/main/protos/google"),
    )?;
    tonic_build::configure()
        .build_server(false)
        .boxed("BlockExtention")
        .compile(
            &["../lib/java-tron/protocol/src/main/protos/api/api.proto"],
            &["../lib/java-tron/protocol/src/main/protos"],
        )?;
    fs::remove_dir_all("../lib/java-tron/protocol/src/main/protos/google")?;
    Ok(())
}

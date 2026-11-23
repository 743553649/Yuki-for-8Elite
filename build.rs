use std::{env, error::Error, fs, path::PathBuf, process::Command};

fn main() {
    if let Err(error) = build_ebpf() {
        panic!("eBPF build failed: {error}");
    }
}

fn build_ebpf() -> Result<(), Box<dyn Error>> {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    println!("cargo:rerun-if-changed=yumi-ebpf/Cargo.toml");
    println!("cargo:rerun-if-changed=yumi-ebpf/src");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=Cargo.lock");

    // Tool installation belongs to CI/developer setup. Source installation here
    // requires a matching LLVM and can fail before any probe is built.
    let linker = Command::new("bpf-linker").arg("--version").output()
        .map_err(|error| format!("cannot run bpf-linker: {error}; install a prebuilt release and add it to PATH: https://github.com/aya-rs/bpf-linker#installation"))?;
    if !linker.status.success() {
        return Err(format!(
            "bpf-linker --version failed ({}): {}",
            linker.status,
            String::from_utf8_lossy(&linker.stderr)
        )
        .into());
    }
    let target = out.join("ebpf_target");
    // Always optimize probes: the BPF verifier must not see debug stack spills.
    let status = Command::new("cargo")
        .args([
            "build",
            "--package",
            "yumi-ebpf",
            "--bins",
            "--release",
            "--target",
            "bpfel-unknown-none",
            "-Z",
            "build-std=core",
            "--target-dir",
        ])
        .arg(&target)
        .current_dir(&manifest)
        // 外层如果由 clippy 驱动（RUSTC_WRAPPER=clippy-driver），嵌套构建也会继承它，
        // 导致 no_std 的 eBPF 探针被 clippy-driver 编译而失败；这里强制回到普通 rustc。
        .env_remove("RUSTC_WRAPPER")
        .env_remove("RUSTC_WORKSPACE_WRAPPER")
        .env_remove("CARGO_ENCODED_RUSTFLAGS")
        .env_remove("RUSTFLAGS")
        .status()?;
    if !status.success() {
        return Err("failed to compile eBPF probes".into());
    }
    for name in ["cpu", "fps-ring", "fps-perf"] {
        fs::copy(
            target.join("bpfel-unknown-none/release").join(name),
            out.join(format!("{name}.ebpf")),
        )?;
    }
    Ok(())
}

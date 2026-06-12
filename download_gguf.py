from huggingface_hub import HuggingFaceHub, hf_hub_download


def download_gguf_model(model_repo_id, file_name, local_dir="./"):
    print(f"Downloading {file_name} from {model_repo_id}...")

    try:
        # Using hf_hub_download is best for a single file
        path = hf_hub_download(
            repo_id=model_repo_id,
            filename=file_name,
            local_dir=local_dir,
        )
        print(f"Successfully downloaded to: {path}")
    except Exception as e:
        print(f"Error downloading model: {e}")


def main():
    REPO = "TheBloke/Mistral-7B-v0.1-GGUF"
    FILE = "mistral-7b.Q4_K_M.gguf"

    download_gguf_model(REPO, FILE)


if __name__ == "__main__":
    main()

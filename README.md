# HAL - A Flutter Chat Client for Ollama

**A feature-rich, local-first, and cross-platform chat application for interacting with Ollama's large language models.**

**

## 📖 Overview

HAL is a Flutter-based front-end for **[Ollama](https://ollama.com/)**, allowing you to run powerful language models locally on your machine. This application provides a clean, intuitive, and highly customizable interface to chat with your models. It saves all your conversations and settings on your device, ensuring privacy and offline access.

With support for multimodal models, voice-to-text, text-to-speech, and extensive settings, HAL aims to be a complete and versatile tool for exploring the capabilities of local LLMs.

## ✨ Features

  - **Ollama Integration**: Connects directly to your local Ollama instance.
  - **Real-time Streaming**: Responses are streamed word-by-word for a dynamic chat experience.
  - **Conversation Management**:
      - Create, rename, and delete conversations.
      - Persistent chat history stored locally using Hive.
      - Easily switch between chats via a navigation drawer.
  - **Rich Media Support**:
      - **Image Input**: Attach images to your prompts to chat with multimodal models (e.g., LLaVA, BakLlava).
      - **Markdown Rendering**: AI responses are beautifully rendered with support for code blocks, lists, and other formatting.
  - **🗣️ Advanced Voice Interaction**:
      - **Voice-to-Text**: Dictate your messages using your device's microphone.
      - **Text-to-Speech**: Have the AI's responses read aloud to you.
      - **Playback Control**: Start and **stop** the voice playback on demand.
      - **Full Voice Mode**: Enable a hands-free experience where the app automatically listens for your next prompt after the AI finishes speaking.
  - **⚙️ Extensive Customization**:
      - Set the Ollama Base URL.
      - Switch between any model available in your Ollama library (e.g., `gemma:2b`, `llama3`).
      - Define a custom **System Prompt** to give your model a specific personality or context.
      - Adjust TTS voice pitch and speed.
      - Toggle Ollama's `think` mode for supported models.
  - **Modern UI/UX**:
      - Sleek, responsive design.
      - Light and Dark theme support.
      - "Typing" indicator while the model generates a response.
      - Quickly copy AI responses to the clipboard.
      - Convenient scroll-to-top/bottom buttons for long conversations.

## 🚀 Getting Started

### Prerequisites

1.  **Ollama**: You must have Ollama installed and running on your machine. You can download it from [ollama.com](https://ollama.com/).

2.  **A Pulled Model**: Make sure you have downloaded at least one model. You can do this by running a command in your terminal:

    ```bash
    ollama run gemma:2b 
    ```

    For image support, pull a multimodal model:

    ```bash
    ollama run llava
    ```

3.  **Flutter SDK**: Ensure you have the Flutter SDK installed on your system. For installation instructions, see the [official Flutter documentation](https://flutter.dev/docs/get-started/install).

### Installation & Setup

1.  **Clone the repository:**

    ```bash
    git clone <your-repository-url>
    cd <your-repository-directory>
    ```

2.  **Install dependencies:**

    ```bash
    flutter pub get
    ```

3.  **Run the code generator:**
    This project uses the `hive_generator` for local database models. You must run the build runner to generate the necessary files (`main.g.dart`).

    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```

4.  **Verify Ollama is running:**
    Open your terminal and ensure the Ollama server is active. By default, the app will try to connect to `http://localhost:11434`.

5.  **Run the application:**

    ```bash
    flutter run
    ```

## 🔧 Configuration and Usage

1.  **Initial Setup**: When you first launch the app, open the **Settings** panel by tapping the gear icon in the app bar.

      * Verify that the **HAL Base URL** matches your Ollama server address.
      * Enter the **Model Name** you want to chat with (e.g., `gemma:2b`). This must match a model you have pulled in Ollama.

2.  **Starting a Chat**:

      * Use the navigation drawer (swipe from the left or tap the menu icon) to start a "New Chat".
      * Type your message in the input field at the bottom and press send.

3.  **Using Voice Mode**:

      * Tap the floating microphone button on the bottom right to enter **Voice Mode**.
      * The app will start listening. When you pause, your speech will be sent as a prompt.
      * The AI's response will be read aloud. After it finishes, the app will automatically start listening again.
      * Tap the button again to exit Voice Mode.

4.  **Attaching Images**:

      * Tap the paperclip icon in the input area to select an image from your gallery.
      * Type an accompanying prompt and send. **Note:** This will only work if you have configured a multimodal model (like `llava`) in the settings.

## 🛠️ Built With

  - **[Flutter](https://flutter.dev/)**: The cross-platform UI toolkit.
  - **[suspicious link removed]**: A lightweight and fast key-value database for local storage.
  - **[http](https://pub.dev/packages/http)**: For making requests to the Ollama API.
  - **[flutter\_markdown](https://www.google.com/search?q=https://pub.dev/packages/flutter_markdown)**: For rendering Markdown content.
  - **[speech\_to\_text](https://pub.dev/packages/speech_to_text)**: For voice input.
  - **[flutter\_tts](https://pub.dev/packages/flutter_tts)**: For voice output.
  - **[image\_picker](https://pub.dev/packages/image_picker)**: For selecting images from the gallery.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

-----
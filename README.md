# HAL: A Flutter Client for Ollama

A feature-rich, local-first, and cross-platform chat application for interacting with local language models through the Ollama API.

## Overview

HAL is a Flutter-based graphical user interface for [Ollama](https://ollama.com/) that allows users to run and chat with powerful language models on their own machine. The application emphasizes privacy and offline access by storing all conversations and settings locally.

With support for multimodal models (image and text), advanced voice I/O, and extensive customization, HAL serves as a complete and versatile tool for exploring the capabilities of local LLMs.

## Core Features

  - **Local-First Ollama Integration**: Connects directly to a local Ollama instance for private, offline-capable conversations.
  - **Full Conversation Management**: Create, rename, delete, and switch between multiple conversations, all stored persistently on-device using Hive.
  - **Rich Chat Experience**: Includes real-time message streaming, full Markdown rendering with code blocks, and image support for multimodal models like LLaVA.
  - **Advanced Voice I/O**:
      - **Voice-to-Text**: Dictate prompts using the device microphone.
      - **Text-to-Speech**: Have model responses read aloud with natural-sounding speech, thanks to intelligent text processing that handles markdown and pauses for punctuation.
      - **Hands-Free Voice Mode**: A continuous conversational mode that listens for your reply after the AI finishes speaking, and automatically exits after a period of inactivity.
  - **Extensive Customization**:
      - Configure the Ollama Base URL and select any available model.
      - Define a custom System Prompt to set the AI's personality and context.
      - Choose from available system voices and adjust speech rate and pitch, with an instant "Test Voice" button.
  - **Modern UI/UX**: A sleek, responsive interface with light/dark themes, copy-to-clipboard functionality, and other user-friendly features.

## Getting Started

### Prerequisites

1.  **Ollama**: Ollama must be installed and running. Download from [ollama.com](https://ollama.com/).
2.  **Model Files**: Pull at least one model via your terminal (e.g., `ollama run gemma:2b`). For multimodal chat, pull a vision model (e.g., `ollama run llava`).
3.  **Flutter SDK**: Ensure the Flutter SDK is installed and configured on your system.

### Installation

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
    This project requires generated files for its local database. This command creates the necessary adapter files (e.g., `conversation.g.dart`) inside the `lib/models/` directory.
    ```bash
    flutter pub run build_runner build --delete-conflicting-outputs
    ```
4.  **Run the application:**
    Ensure your local Ollama server is running, then launch the app:
    ```bash
    flutter run
    ```

## Project Structure

The project is organized into a clean and scalable structure:

```
lib/
├── main.dart                 # App entry point and MaterialApp setup
├── hive_setup.dart           # Hive database initialization logic
|
├── pages/
│   ├── chat_page.dart          # Main chat UI and state management
│   └── settings_page.dart      # Settings UI and state management
|
├── models/
│   └── *.dart                  # Hive data models (Conversation, ChatMessage)
|
└── widgets/
    └── *.dart                  # Reusable UI components (ChatBubble, etc.)
```

## Configuration and Usage

1.  **Initial Setup**: On first launch, open **Settings** (gear icon). Verify the **Base URL** points to your Ollama server and enter the **Model Name** you wish to use.
2.  **Voice Mode**: Tap the floating microphone button to enter Voice Mode. The app will listen for your prompt. After the AI responds, it will listen again. If you are silent for 20 seconds, the app will announce it is exiting and turn off the microphone. Tap the button again to exit manually at any time.

## Built With

  - **[Flutter](https://flutter.dev/)**: The cross-platform UI toolkit.
  - **[Hive](https://www.google.com/search?q=https://pub.dev/packages/hive)**: A lightweight and fast key-value database.
  - **[http](https://pub.dev/packages/http)**: For making requests to the Ollama API.
  - **[flutter\_markdown](https://www.google.com/search?q=https://pub.dev/packages/flutter_markdown)**: For rendering Markdown content.
  - **[speech\_to\_text](https://pub.dev/packages/speech_to_text)**: For voice input.
  - **[flutter\_tts](https://pub.dev/packages/flutter_tts)**: For voice output.
  - **[image\_picker](https://pub.dev/packages/image_picker)**: For selecting images.

## Contributing

Contributions are welcome. Please feel free to open an issue for bug reports and feature requests, or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
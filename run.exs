host = if app = System.get_env("FLY_APP_NAME"), do: "#{app}.fly.dev", else: "localhost"

Application.put_env(:phoenix, :json_library, Jason)

Application.put_env(:ex_whisper, ExWhisper.Endpoint,
  url: [host: host],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4000"),
    transport_options: [socket_opts: [:inet6]]
  ],
  server: true,
  live_view: [signing_salt: :crypto.strong_rand_bytes(8) |> Base.encode16()],
  secret_key_base: :crypto.strong_rand_bytes(32) |> Base.encode16(),
  pubsub_server: ExWhisper.PubSub
)

Mix.install([
  {:plug_cowboy, "~> 2.6"},
  {:jason, "~> 1.4"},
  {:phoenix, "~> 1.7"},
  {:phoenix_live_view, "~> 0.18.18"},
  {:bumblebee, "~> 0.2.0"},
  {:nx, "~> 0.5.2"},
  {:exla, "~> 0.5.2"}
])

Application.put_env(:nx, :default_backend, EXLA.Backend)

defmodule ExWhisper.Layouts do
  use Phoenix.Component

  def render("live.html", assigns) do
    ~H"""
      <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.2/priv/static/phoenix.min.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.18.18/priv/static/phoenix_live_view.min.js"></script>
      <script src="https://cdn.tailwindcss.com"></script>
      <script>
        const AudioInput = {
          mounted() {
            const DROP_CLASSES = ["bg-blue-100", "border-blue-300"]
            this.boundHeight = parseInt(this.el.dataset.height)
            this.boundWidth  = parseInt(this.el.dataset.width)
            this.inputEl = this.el.querySelector(`#${this.el.id}-input`)
            this.previewEl = this.el.querySelector(`#${this.el.id}-preview`)

            this.el.addEventListener("click", e => this.inputEl.click())
            this.inputEl.addEventListener("change", e => this.loadFile(e.target.files))
            this.el.addEventListener("dragover", e => {
              e.stopPropagation()
              e.preventDefault()
              e.dataTransfer.dropEffect = "copy"
            })
            this.el.addEventListener("drop", e => {
              e.stopPropagation()
              e.preventDefault()
              this.loadFile(e.dataTransfer.files)
            })
            this.el.addEventListener("dragenter", e => this.el.classList.add(...DROP_CLASSES))
            this.el.addEventListener("drop", e => this.el.classList.remove(...DROP_CLASSES))
            this.el.addEventListener("dragleave", e => {
              if(!this.el.contains(e.relatedTarget)){ this.el.classList.remove(...DROP_CLASSES) }
            })
          },

          loadFile(files) {
            const file  = files && files[0]
            if (!file) { return }
            const reader = new FileReader()
            reader.onload = (readerEvent) => {
              const audioEl = document.createElement("audio")
              audioEl.addEventListener("loadedmetadata", (loadEvent) => {
                this.setPreview(audioEl)
                this.upload("audio", [file])
              })
              audioEl.src = readerEvent.target.result
            }
            reader.readAsDataURL(file)
          },
          
          setPreview(audioEl) {
            const previewAudioEl = audioEl.cloneNode()
            previewAudioEl.style.maxHeight = "100%"
            previewAudioEl.controls = true
            this.previewEl.replaceChildren(previewAudioEl)
          }

        }
        const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {hooks: {AudioInput}})
        liveSocket.connect()
      </script>
      <%= @inner_content %>
    """
  end
end

defmodule ExWhisper.ErrorView do
  def render(_, _), do: "error"
end

defmodule ExWhisper.AudioLive do
  use Phoenix.LiveView, layout: {ExWhisper.Layouts, :live}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(text: nil, running: false, task_ref: nil, uploading: false)
     |> allow_upload(:audio,
       accept: [".mp3", ".wav", ".aac"],
       max_entries: 1,
       max_file_size: 10 * 1000 * 1000,
       progress: &handle_progress/3,
       auto_upload: true
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen flex items-center justify-center antialiased bg-gray-100">
      <div class="flex flex-col items-center w-1/2">
        <h1 class="text-slate-900 font-extrabold text-3xl tracking-tight text-center">Elixir speech to text demo</h1>
        <form class="m-0 flex flex-col items-center space-y-2 mt-8" phx-change="noop" phx-submit="noop">
          <.audio_input id="audio" upload={@uploads.audio} height={224} width={224} />
        </form>
          <%= if @uploading do %>
            <div class="mt-6 flex space-x-1.5 items-center text-gray-600 text-xl">
              <span>Uploading:</span>
              <.spinner />
            </div>
          <% end %>
        <div class="mt-6 flex flex-col space-x-1.5 items-center text-gray-600 text-xl">
          <span>Text:</span>
          <%= if @running do %>
            <.spinner />
          <% else %>
            <div class="text-gray-900 font-medium overflow-y-scroll h-[300px]"><%= @text || "?" %></div>
          <% end %>
        </div>
        <p class="text-lg text-center max-w-3xl mx-auto fixed top-2 right-2">
          <a href="https://github.com/rakshans1/ex-whisper" class="ml-6 text-sky-500 hover:text-sky-700 font-mono font-medium">
            View the source
            <span class="sr-only">view source on GitHub</span>
            <svg viewBox="0 0 16 16" class="inline w-6 h-6" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg>
          </a>
        </p>
      </div>
    </div>
    """
  end

  defp audio_input(assigns) do
    ~H"""
    <div
      id={@id}
      class="inline-flex p-4 border-2 border-dashed border-gray-200 rounded-lg cursor-pointer bg-white"
      phx-hook="AudioInput"
      data-height={@height}
      data-width={@width}
    >
      <.live_file_input upload={@upload} class="hidden" />
      <input id={"#{@id}-input"} type="file" class="hidden" accept="audio/*" alt="audio"/>
      <div
        class="h-[300px] w-[300px] flex items-center justify-center"
        id={"#{@id}-preview"}
        phx-update="ignore"
      >
        <div class="text-gray-500 text-center">
          Drag an audio file here or click to open file browser
        </div>
      </div>
    </div>
    """
  end

  defp spinner(assigns) do
    ~H"""
    <svg phx-no-format class="inline mr-2 w-4 h-4 text-gray-200 animate-spin fill-blue-600" viewBox="0 0 100 101" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z" fill="currentColor" />
      <path d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z" fill="currentFill" />
    </svg>
    """
  end

  def handle_progress(:audio, entry, socket) do
    if entry.done? do
      socket
      |> consume_uploaded_entries(:audio, fn meta, _ ->
        dest = Path.join(["static", "uploads", Path.basename(meta.path)])
        File.cp!(meta.path, dest)
        {:ok, dest}
      end)
      |> case do
        nil ->
          {:noreply, socket}

        [path] ->
          pid = self()

          task =
            ExWhisper.Audio.speech_to_text(path, 20, fn ss, text ->
              send(pid, {:segment_transcribed, {ss, text}})
            end)

          {:noreply, assign(socket, running: true, task_ref: task.ref, uploading: false)}
      end
    else
      {:noreply, assign(socket, uploading: true)}
    end
  end

  # We need phx-change and phx-submit on the form for live uploads
  def handle_event("noop", %{}, socket) do
    {:noreply, socket}
  end

  def handle_info({:segment_transcribed, result}, socket) do
    {ss, text} = result

    text =
      case socket.assigns.text do
        nil -> text
        t -> t <> text
      end

    {:noreply, assign(socket, running: false, text: text)}
  end

  def handle_info({ref, result}, %{assigns: %{task_ref: ref}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, socket}
  end
end

defmodule ExWhisper.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", ExWhisper do
    pipe_through(:browser)

    live("/", AudioLive, :index)
  end
end

defmodule ExWhisper.Endpoint do
  use Phoenix.Endpoint, otp_app: :ex_whisper

  socket("/live", Phoenix.LiveView.Socket)

  plug(ExWhisper.Router)
end

defmodule ExWhisper.Audio do
  def speech_to_text(path, chunk_time, func) do
    Task.async(fn ->
      stat = ExWhisper.Audio.get_stat(path)
      duration = string_to_numeric(stat |> Map.get("duration")) |> ceil()

      0..duration//chunk_time
      |> Task.async_stream(
        fn ss ->
          args = ~w(-ac 1 -ar 16k -f f32le -ss #{ss} -t #{chunk_time} -v quiet -)
          {data, 0} = System.cmd("ffmpeg", ["-i", path] ++ args)
          {ss, Nx.Serving.batched_run(ExWhisper.Serving, Nx.from_binary(data, :f32))}
        end,
        max_concurrency: 4,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {ss, %{results: [%{text: text}]}}} ->
        func.(ss, text)
      end)
    end)
  end

  def get_stat(path) do
    args = ~w(-v 0 -print_format json -show_streams -show_format)
    {data, 0} = System.cmd("ffprobe", ["-i", path] ++ args)
    data |> Jason.decode!() |> Map.get("streams") |> Enum.at(0)
  end

  @spec string_to_numeric(binary()) :: float() | number() | nil
  defp string_to_numeric(val) when is_binary(val),
    do: _string_to_numeric(Integer.parse(val), val)

  defp _string_to_numeric(:error, _val), do: nil
  defp _string_to_numeric({num, ""}, _val), do: num
  defp _string_to_numeric({num, ".0"}, _val), do: num
  defp _string_to_numeric({_num, _str}, val), do: elem(Float.parse(val), 0)
end

# Application startup
{:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-base"})
{:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-base"})
{:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-base"})

serving =
  Bumblebee.Audio.speech_to_text(whisper, featurizer, tokenizer,
    max_new_tokens: 100,
    compile: [batch_size: 5],
    defn_options: [compiler: EXLA]
  )

# Dry run for copying cached mix install from builder to runner
if System.get_env("EXS_DRY_RUN") == "true" do
  System.halt(0)
else
  {:ok, _} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: ExWhisper.PubSub},
        ExWhisper.Endpoint,
        {Nx.Serving, serving: serving, name: ExWhisper.Serving, batch_timeout: 100}
      ],
      strategy: :one_for_one
    )

  path = Path.join(["static", "uploads"])
  File.mkdir_p(path)

  Process.sleep(:infinity)
end

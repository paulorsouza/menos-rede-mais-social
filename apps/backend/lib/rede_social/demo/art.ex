defmodule RedeSocial.Demo.Art do
  @moduledoc """
  Ilustrações em SVG para os posts de foto da demonstração. São geradas aqui
  para a demo não depender de fotos de terceiros.
  """

  @width 1200
  @height 900

  def svg(scene) do
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@width} #{@height}" width="#{@width}" height="#{@height}">
    #{scene(scene)}
    </svg>
    """
  end

  defp gradient(id, top, bottom) do
    """
    <defs><linearGradient id="#{id}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#{top}"/><stop offset="1" stop-color="#{bottom}"/>
    </linearGradient></defs>
    """
  end

  defp scene(:sunset) do
    gradient("sky", "#ff9e5e", "#7b3f8c") <>
      gradient("sea", "#2b4c7e", "#0d1b2a") <>
      """
      <rect width="1200" height="900" fill="url(#sky)"/>
      <circle cx="600" cy="520" r="130" fill="#ffd27a"/>
      <rect y="560" width="1200" height="340" fill="url(#sea)"/>
      <path d="M0 600 Q300 580 600 600 T1200 600 V620 H0Z" fill="#ffd27a" opacity="0.35"/>
      <rect x="880" y="300" width="56" height="270" fill="#1b1b2f"/>
      <polygon points="868,300 948,300 908,250" fill="#1b1b2f"/>
      <rect x="896" y="270" width="24" height="26" fill="#ffe8a3"/>
      <path d="M760 570 L1060 570 L1100 610 L720 610Z" fill="#1b1b2f"/>
      """
  end

  defp scene(:river) do
    gradient("dawn", "#f7b2a3", "#9fd3c7") <>
      """
      <rect width="1200" height="900" fill="url(#dawn)"/>
      <circle cx="300" cy="260" r="70" fill="#fff1d6" opacity="0.9"/>
      <path d="M0 520 C300 480 500 600 800 540 S1100 500 1200 520 V900 H0Z" fill="#3a7d7c"/>
      <path d="M0 600 C300 560 500 680 800 620 S1100 580 1200 600" stroke="#cdeee6" stroke-width="6" fill="none" opacity="0.6"/>
      <g fill="#1f4e3d">
        <circle cx="120" cy="470" r="90"/><circle cx="230" cy="440" r="110"/><circle cx="360" cy="480" r="80"/>
        <circle cx="900" cy="460" r="100"/><circle cx="1030" cy="430" r="120"/><circle cx="1160" cy="470" r="90"/>
      </g>
      <path d="M520 700 L700 700 L680 730 L540 730Z" fill="#5b3a29"/>
      """
  end

  defp scene(:field) do
    gradient("grass", "#6fbf4c", "#2f7a2f") <>
      """
      <rect width="1200" height="900" fill="#b8d8f0"/>
      <ellipse cx="300" cy="140" rx="160" ry="50" fill="#ffffff" opacity="0.9"/>
      <ellipse cx="850" cy="110" rx="200" ry="60" fill="#ffffff" opacity="0.8"/>
      <rect y="300" width="1200" height="600" fill="url(#grass)"/>
      <g stroke="#f4f4f4" stroke-width="8" fill="none" opacity="0.85">
        <rect x="120" y="360" width="960" height="480"/>
        <line x1="600" y1="360" x2="600" y2="840"/>
        <circle cx="600" cy="600" r="90"/>
        <rect x="120" y="500" width="140" height="200"/><rect x="940" y="500" width="140" height="200"/>
      </g>
      <circle cx="680" cy="640" r="22" fill="#ffffff"/>
      <path d="M672 630 l16 0 l-8 14z" fill="#222"/>
      """
  end

  defp scene(:food) do
    """
    <rect width="1200" height="900" fill="#8b5a3c"/>
    <g stroke="#7a4d33" stroke-width="4">
      <line x1="0" y1="150" x2="1200" y2="150"/><line x1="0" y1="330" x2="1200" y2="330"/>
      <line x1="0" y1="510" x2="1200" y2="510"/><line x1="0" y1="690" x2="1200" y2="690"/>
    </g>
    <circle cx="600" cy="450" r="300" fill="#f3efe6"/>
    <circle cx="600" cy="450" r="240" fill="#ffffff"/>
    <g fill="#f2c14e" stroke="#d99a2b" stroke-width="6">
      <circle cx="520" cy="380" r="62"/><circle cx="660" cy="370" r="58"/><circle cx="600" cy="480" r="66"/>
      <circle cx="480" cy="520" r="56"/><circle cx="720" cy="510" r="60"/>
    </g>
    <circle cx="1020" cy="200" r="110" fill="#c0392b"/><circle cx="1020" cy="200" r="80" fill="#e74c3c"/>
    <rect x="120" y="640" width="200" height="40" rx="20" fill="#d8c3a5"/>
    """
  end

  defp scene(:food2) do
    """
    <rect width="1200" height="900" fill="#e9dcc4"/>
    <rect x="0" y="0" width="1200" height="900" fill="none" stroke="#c9a96e" stroke-width="40"/>
    <ellipse cx="600" cy="470" rx="360" ry="250" fill="#ffffff"/>
    <ellipse cx="600" cy="450" rx="280" ry="190" fill="#f5c542"/>
    <g fill="#e74c3c"><circle cx="500" cy="420" r="28"/><circle cx="640" cy="390" r="24"/><circle cx="700" cy="500" r="26"/></g>
    <g fill="#2e7d32"><circle cx="560" cy="500" r="18"/><circle cx="740" cy="430" r="16"/><circle cx="460" cy="490" r="14"/></g>
    <g fill="#f4e1b0"><ellipse cx="600" cy="300" rx="40" ry="16"/><ellipse cx="420" cy="400" rx="36" ry="14"/></g>
    """
  end

  defp scene(:bread) do
    gradient("warm", "#f6d7a7", "#e0a96d") <>
      """
      <rect width="1200" height="900" fill="url(#warm)"/>
      <rect x="100" y="560" width="1000" height="220" rx="30" fill="#6d4c41"/>
      <g fill="#c8823b" stroke="#8d5524" stroke-width="6">
        <ellipse cx="300" cy="540" rx="170" ry="80"/><ellipse cx="600" cy="520" rx="190" ry="90"/>
        <ellipse cx="900" cy="540" rx="170" ry="80"/>
      </g>
      <g stroke="#8d5524" stroke-width="8" fill="none">
        <path d="M230 520 l40 -30 M300 530 l40 -30"/><path d="M530 500 l40 -30 M610 505 l40 -30"/>
        <path d="M830 520 l40 -30 M900 530 l40 -30"/>
      </g>
      <g stroke="#ffffff" stroke-width="10" fill="none" opacity="0.7" stroke-linecap="round">
        <path d="M560 380 q-30 -40 0 -80 q30 -40 0 -80"/><path d="M650 380 q-30 -40 0 -80 q30 -40 0 -80"/>
      </g>
      """
  end

  defp scene(:music) do
    """
    <rect width="1200" height="900" fill="#1e1b3a"/>
    <circle cx="600" cy="450" r="380" fill="#2c2760"/>
    <g transform="rotate(-25 600 450)">
      <rect x="585" y="80" width="30" height="330" fill="#3e2723"/>
      <ellipse cx="600" cy="560" rx="170" ry="190" fill="#d18b47"/>
      <ellipse cx="600" cy="460" rx="120" ry="130" fill="#d18b47"/>
      <circle cx="600" cy="500" r="50" fill="#3e2723"/>
      <g stroke="#f5f5f5" stroke-width="3"><line x1="592" y1="90" x2="592" y2="700"/><line x1="608" y1="90" x2="608" y2="700"/></g>
    </g>
    <g fill="#ffd166">
      <circle cx="220" cy="300" r="22"/><rect x="238" y="200" width="8" height="100"/>
      <circle cx="980" cy="260" r="22"/><rect x="998" y="160" width="8" height="100"/>
    </g>
    """
  end

  defp scene(:tech) do
    """
    <rect width="1200" height="900" fill="#0b3d91"/>
    <g stroke="#1e5bb8" stroke-width="2">
      #{Enum.map_join(0..12, "", fn i -> ~s(<line x1="#{i * 100}" y1="0" x2="#{i * 100}" y2="900"/>) end)}
    </g>
    #{Enum.map_join([{150, 280}, {480, 280}, {810, 280}, {150, 560}, {480, 560}, {810, 560}], "", fn {x, y} -> ~s(<rect x="#{x}" y="#{y}" width="240" height="160" rx="12" fill="#0f172a" stroke="#93c5fd" stroke-width="6"/><rect x="#{x + 20}" y="#{y + 20}" width="200" height="12" fill="#38bdf8"/><rect x="#{x + 20}" y="#{y + 46}" width="140" height="12" fill="#a5f3fc"/><rect x="#{x + 95}" y="#{y + 160}" width="50" height="30" fill="#93c5fd"/>) end)}
    """
  end

  defp scene(:lily) do
    """
    <rect width="1200" height="900" fill="#1f6f5c"/>
    <g fill="#2e8b57" stroke="#1b5e3f" stroke-width="6">
      <path d="M300 300 m-170 0 a170 170 0 1 0 340 0 a170 170 0 1 0 -340 0z"/>
      <path d="M850 560 m-210 0 a210 210 0 1 0 420 0 a210 210 0 1 0 -420 0z"/>
      <path d="M420 700 m-120 0 a120 120 0 1 0 240 0 a120 120 0 1 0 -240 0z"/>
    </g>
    <g fill="#1f6f5c"><polygon points="300,300 470,280 470,320"/><polygon points="850,560 1060,530 1060,590"/></g>
    <g fill="#f8a5c2"><ellipse cx="860" cy="520" rx="30" ry="60"/><ellipse cx="820" cy="540" rx="30" ry="55" transform="rotate(-30 820 540)"/><ellipse cx="900" cy="540" rx="30" ry="55" transform="rotate(30 900 540)"/></g>
    <circle cx="860" cy="560" r="18" fill="#ffd166"/>
    """
  end

  defp scene(:city) do
    colors = ["#e63946", "#f4a261", "#2a9d8f", "#e9c46a", "#457b9d", "#f28482", "#90be6d"]

    houses =
      colors
      |> Enum.with_index()
      |> Enum.map_join("", fn {color, i} ->
        x = 40 + i * 165
        height = 380 + rem(i * 73, 160)
        y = 820 - height

        ~s(<rect x="#{x}" y="#{y}" width="160" height="#{height}" fill="#{color}"/>) <>
          ~s(<rect x="#{x + 30}" y="#{y + 50}" width="36" height="56" fill="#fdf0d5"/>) <>
          ~s(<rect x="#{x + 94}" y="#{y + 50}" width="36" height="56" fill="#fdf0d5"/>) <>
          ~s(<rect x="#{x + 62}" y="#{y + height - 90}" width="36" height="90" fill="#5c4033"/>)
      end)

    """
    <rect width="1200" height="900" fill="#a8dadc"/>
    #{houses}
    <rect y="820" width="1200" height="80" fill="#b5a397"/>
    """
  end
end

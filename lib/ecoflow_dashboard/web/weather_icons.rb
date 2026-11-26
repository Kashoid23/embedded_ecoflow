# frozen_string_literal: true

module EcoflowDashboard
  module Web
    # Inline SVG weather icons (24×24, stroked), so they look the same on any display —
    # no emoji font or internet access needed. Colours come from the w-* classes.
    module WeatherIcons
      CLOUD      = '<path class="w-cloud" d="M7 19h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.2 11.2 3.9 3.9 0 0 0 7 19z"/>'
      CLOUD_HIGH = '<path class="w-cloud" d="M7 15h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.2 7.2 3.9 3.9 0 0 0 7 15z"/>'
      SUN        = '<g class="w-sun"><circle cx="12" cy="12" r="4"/>' \
                   '<path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></g>'
      MOON       = '<path class="w-moon" d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>'

      ICONS = {
        clear_day: SUN,
        clear_night: MOON,
        partly_day: %(<g transform="translate(.5 .5) scale(.6)">#{SUN}</g>#{CLOUD}),
        partly_night: %(<g transform="translate(1 1) scale(.55)">#{MOON}</g>#{CLOUD}),
        cloudy: CLOUD,
        fog: '<path class="w-cloud" d="M4 9h16M2 13h20M5 17h14"/>',
        rain: %(#{CLOUD_HIGH}<path class="w-rain" d="M8 18l-1 3M12 18l-1 3M16 18l-1 3"/>),
        snow: %(#{CLOUD_HIGH}<g class="w-snow"><circle cx="8" cy="19" r="1"/><circle cx="12" cy="21" r="1"/><circle cx="16" cy="19" r="1"/></g>),
        thunder: %(#{CLOUD_HIGH}<path class="w-bolt" d="M13 15l-3 4h4l-2 4"/>)
      }.freeze

      def weather_icon(report)
        name = if %i[clear partly].include?(report.kind)
                 :"#{report.kind}_#{report.day ? 'day' : 'night'}"
               else
                 report.kind
               end
        %(<svg viewBox="0 0 24 24" aria-hidden="true">#{ICONS.fetch(name)}</svg>)
      end

      # 3.4 -> "3°", -2.6 -> "−3°" (typographic minus)
      def temperature(celsius)
        degrees = celsius.round
        "#{'−' if degrees.negative?}#{degrees.abs}°"
      end
    end
  end
end

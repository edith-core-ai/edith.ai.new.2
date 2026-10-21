import 'package:google_generative_ai/google_generative_ai.dart';

/// Declares every tool EDITH can call to Gemini.
///
/// Gemini 0.4.x API: Tool takes a List<FunctionDeclaration>, not a Map.
/// FunctionDeclaration is positional (name, description, [parameters]).
/// Schema is a factory: Schema.string(...), Schema.object(...) etc.
class ToolRegistry {
  static List<Tool> all() => [
        Tool(
          functionDeclarations: [
            // ─────────── Tier 1 ───────────
            FunctionDeclaration(
              'send_sms',
              'Opens the SMS app with a prefilled recipient and message. '
                  'The user taps send to confirm. Use send_sms_direct for '
                  'no-confirmation sending when the user explicitly wants it.',
              Schema.object(
                properties: {
                  'to': Schema.string(
                      description: 'Phone number or contact name'),
                  'body': Schema.string(description: 'Message text'),
                },
                requiredProperties: ['to', 'body'],
              ),
            ),
            FunctionDeclaration(
              'send_sms_direct',
              'Sends an SMS directly without opening the SMS app. Use only '
                  'when the user explicitly asks to send a text.',
              Schema.object(
                properties: {
                  'to': Schema.string(
                      description:
                          'Phone number, or a contact name to look up'),
                  'body': Schema.string(description: 'Message text'),
                },
                requiredProperties: ['to', 'body'],
              ),
            ),
            FunctionDeclaration(
              'make_call',
              'Opens the dialer with a phone number ready to call.',
              Schema.object(
                properties: {
                  'number': Schema.string(description: 'Phone number'),
                },
                requiredProperties: ['number'],
              ),
            ),
            FunctionDeclaration(
              'open_url',
              'Opens a web URL in the device browser.',
              Schema.object(
                properties: {
                  'url': Schema.string(description: 'Full http(s) URL'),
                },
                requiredProperties: ['url'],
              ),
            ),
            FunctionDeclaration(
              'share_text',
              'Opens the share sheet with the given text.',
              Schema.object(
                properties: {
                  'text': Schema.string(description: 'Text to share'),
                },
                requiredProperties: ['text'],
              ),
            ),
            FunctionDeclaration(
              'set_alarm',
              'Sets an alarm on the device clock.',
              Schema.object(
                properties: {
                  'hour': Schema.integer(description: '24h hour 0-23'),
                  'minute': Schema.integer(description: 'Minute 0-59'),
                  'label': Schema.string(description: 'Alarm label'),
                },
                requiredProperties: ['hour', 'minute'],
              ),
            ),
            FunctionDeclaration(
              'set_reminder',
              'Opens the calendar app to create a reminder event.',
              Schema.object(
                properties: {
                  'title': Schema.string(description: 'Event title'),
                  'start_iso':
                      Schema.string(description: 'ISO 8601 start time'),
                },
                requiredProperties: ['title', 'start_iso'],
              ),
            ),
            FunctionDeclaration(
              'get_clipboard',
              'Returns the current text on the clipboard.',
              Schema.object(properties: {}),
            ),
            FunctionDeclaration(
              'set_clipboard',
              'Copies text to the clipboard.',
              Schema.object(
                properties: {
                  'text': Schema.string(description: 'Text to copy'),
                },
                requiredProperties: ['text'],
              ),
            ),
            FunctionDeclaration(
              'get_weather',
              'Fetches current weather for a city.',
              Schema.object(
                properties: {
                  'city': Schema.string(description: 'City name'),
                },
                requiredProperties: ['city'],
              ),
            ),
            FunctionDeclaration(
              'get_news',
              'Fetches latest headlines on a topic.',
              Schema.object(
                properties: {
                  'topic': Schema.string(description: 'Topic or query'),
                },
                requiredProperties: ['topic'],
              ),
            ),
            FunctionDeclaration(
              'play_music',
              'Searches YouTube Music for a song, artist, or playlist.',
              Schema.object(
                properties: {
                  'query': Schema.string(description: 'Song or artist'),
                },
                requiredProperties: ['query'],
              ),
            ),
            FunctionDeclaration(
              'open_app',
              'Opens an installed app by its name, e.g. "WhatsApp" or "Settings".',
              Schema.object(
                properties: {
                  'name': Schema.string(
                      description: 'App name as shown on the home screen'),
                },
                requiredProperties: ['name'],
              ),
            ),

            FunctionDeclaration(
              'web_search',
              'Searches the live internet. Use for news, release dates, '
                  'prices, scores, anything current or that you are not sure '
                  'about. Returns an answer with sources.',
              Schema.object(
                properties: {
                  'query': Schema.string(description: 'What to search for'),
                },
                requiredProperties: ['query'],
              ),
            ),
            FunctionDeclaration(
              'read_webpage',
              'Opens a web page and returns its text. Use after web_search '
                  'to read a result, or when the user gives a link.',
              Schema.object(
                properties: {
                  'url': Schema.string(description: 'Full http(s) address'),
                },
                requiredProperties: ['url'],
              ),
            ),

            FunctionDeclaration(
              'remember',
              'Saves one short lasting fact about the user to long-term '
                  'memory. Use when they share something lasting or say '
                  '"remember this".',
              Schema.object(
                properties: {
                  'fact': Schema.string(description: 'One short fact'),
                },
                requiredProperties: ['fact'],
              ),
            ),
            FunctionDeclaration(
              'forget',
              'Removes saved memories that contain the given text.',
              Schema.object(
                properties: {
                  'text': Schema.string(description: 'Text to forget'),
                },
                requiredProperties: ['text'],
              ),
            ),
            FunctionDeclaration(
              'generate_image',
              'Creates a picture from a description and shows it in the '
                  'chat. Use when asked to draw, create or generate an image.',
              Schema.object(
                properties: {
                  'prompt': Schema.string(
                      description: 'Detailed description of the picture'),
                },
                requiredProperties: ['prompt'],
              ),
            ),

            FunctionDeclaration(
              'look_at_screen',
              'Takes a screenshot of the phone screen and looks at it. Use '
                  'when asked to look at, read or explain what is on the '
                  'screen. Tell Hilal to switch to the right app first; the '
                  'capture happens after the delay.',
              Schema.object(
                properties: {
                  'seconds': Schema.integer(
                      description: 'Seconds to wait before capture (default 4)'),
                },
              ),
            ),

            // ─────────── Tier 2 ───────────
            FunctionDeclaration(
              'list_calendar_events',
              'Lists upcoming Google Calendar events for the signed-in user.',
              Schema.object(
                properties: {
                  'max': Schema.integer(description: 'Max events (default 10)'),
                },
              ),
            ),
            FunctionDeclaration(
              'create_calendar_event',
              'Creates a Google Calendar event.',
              Schema.object(
                properties: {
                  'title': Schema.string(description: 'Event title'),
                  'start_iso':
                      Schema.string(description: 'ISO 8601 start time'),
                  'end_iso': Schema.string(
                      description: 'Optional ISO 8601 end time'),
                },
                requiredProperties: ['title', 'start_iso'],
              ),
            ),
            FunctionDeclaration(
              'list_emails',
              'Lists recent unread Gmail messages.',
              Schema.object(
                properties: {
                  'max': Schema.integer(description: 'Max (default 5)'),
                },
              ),
            ),
            FunctionDeclaration(
              'send_email',
              'Sends an email via the signed-in Gmail account.',
              Schema.object(
                properties: {
                  'to': Schema.string(description: 'Recipient email'),
                  'subject': Schema.string(description: 'Subject'),
                  'body': Schema.string(description: 'Body text'),
                },
                requiredProperties: ['to', 'subject', 'body'],
              ),
            ),

            // ─────────── Tier 3 ───────────
            FunctionDeclaration(
              'read_contacts',
              'Reads the device contacts list.',
              Schema.object(
                properties: {
                  'filter': Schema.string(
                      description:
                          'Optional name fragment to filter by.'),
                },
              ),
            ),
            FunctionDeclaration(
              'lookup_contact',
              'Looks up a phone number for a contact by name.',
              Schema.object(
                properties: {
                  'name': Schema.string(description: 'Contact name fragment'),
                },
                requiredProperties: ['name'],
              ),
            ),
            FunctionDeclaration(
              'read_notifications',
              'Reads recent device notifications. Requires notification '
                  'listener enabled.',
              Schema.object(
                properties: {
                  'limit': Schema.integer(description: 'Max (default 10)'),
                },
              ),
            ),

            // ─────────── Tier 4 ───────────
            FunctionDeclaration(
              'whatsapp_message',
              'Sends a WhatsApp message to a contact name or phone number. '
                  'Asks the user to approve, then types and sends it.',
              Schema.object(
                properties: {
                  'phone': Schema.string(
                      description: 'Contact name, or phone with country code'),
                  'message': Schema.string(description: 'Message text'),
                  'business': Schema.boolean(
                      description: 'True to use WhatsApp Business'),
                },
                requiredProperties: ['phone', 'message'],
              ),
            ),
            FunctionDeclaration(
              'whatsapp_call',
              'Opens WhatsApp chat screen for a phone number.',
              Schema.object(
                properties: {
                  'phone': Schema.string(
                      description: 'Phone with country code'),
                },
                requiredProperties: ['phone'],
              ),
            ),
            FunctionDeclaration(
              'whatsapp_share',
              'Opens WhatsApp with a message and no specific recipient.',
              Schema.object(
                properties: {
                  'message': Schema.string(description: 'Message to share'),
                },
                requiredProperties: ['message'],
              ),
            ),
            FunctionDeclaration(
              'automate_task',
              'Performs a task on the phone using accessibility automation. '
                  'Use when the user asks you to operate another app.',
              Schema.object(
                properties: {
                  'instruction': Schema.string(
                      description:
                          'Plain-language goal, e.g. "Open Settings and turn on WiFi"'),
                },
                requiredProperties: ['instruction'],
              ),
            ),
          ],
        ),
      ];
}
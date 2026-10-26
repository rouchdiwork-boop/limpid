/// Événement Server-Sent Events décodé.
class SseEvent {
  /// Crée un événement.
  const SseEvent({required this.data, this.event});

  /// Nom d'événement (`event:`), quand le serveur l'envoie.
  final String? event;

  /// Charge utile (`data:`), une ou plusieurs lignes fusionnées.
  final String data;
}

/// Décodeur SSE ligne à ligne.
///
/// Les données peuvent être réparties sur plusieurs lignes `data:` ; elles
/// sont fusionnées jusqu'à la ligne vide qui clôt l'événement.
class SseDecoder {
  const SseDecoder._();

  /// Convertit un flux de lignes brutes en flux d'événements SSE.
  static Stream<SseEvent> decode(Stream<String> lines) async* {
    final List<String> dataBuffer = <String>[];
    String? eventName;

    await for (final String rawLine in lines) {
      final String line = _stripCarriageReturn(rawLine);
      if (line.isEmpty) {
        if (dataBuffer.isNotEmpty) {
          yield SseEvent(event: eventName, data: dataBuffer.join('\n'));
        }
        dataBuffer.clear();
        eventName = null;
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      final _SseField field = _parseField(line);
      switch (field.name) {
        case 'event':
          eventName = field.value;
          break;
        case 'data':
          dataBuffer.add(field.value);
          break;
        default:
          break;
      }
    }

    if (dataBuffer.isNotEmpty) {
      yield SseEvent(event: eventName, data: dataBuffer.join('\n'));
    }
  }

  static String _stripCarriageReturn(String line) {
    if (line.endsWith('\r')) {
      return line.substring(0, line.length - 1);
    }
    return line;
  }

  static _SseField _parseField(String line) {
    final int separator = line.indexOf(':');
    if (separator < 0) {
      return const _SseField(name: '', value: '');
    }
    final String name = line.substring(0, separator);
    String value = line.substring(separator + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    return _SseField(name: name, value: value);
  }
}

class _SseField {
  const _SseField({required this.name, required this.value});

  final String name;
  final String value;
}

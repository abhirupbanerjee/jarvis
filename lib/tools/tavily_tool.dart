// lib/tools/tavily_tool.dart — Tavily Search Tool Definition
//
// Web search integration via tavily_dart REST API.
// Used as a Gemini function tool for current information retrieval.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tavily_dart/tavily_dart.dart';

import 'tool_registry.dart';

final tavilySearchTool = ToolDefinition(
  name: 'tavily_search',
  description:
      'Search the web for current information using Tavily. '
      'Use this when you need up-to-date facts, news, or information '
      'beyond your knowledge cutoff.',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description':
            'The search query. Be specific and include relevant keywords.',
      },
      'max_results': {
        'type': 'integer',
        'description': 'Maximum number of results (1-10, default: 5)',
      },
      'search_depth': {
        'type': 'string',
        'enum': ['basic', 'advanced'],
        'description':
            'basic for quick results (cheaper), advanced for comprehensive multi-source research',
      },
    },
    'required': ['query'],
  },
  executor: (args) async {
    final apiKey = dotenv.env['TAVILY_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'PLACEHOLDER_SET_YOUR_KEY_HERE') {
      return {
        'answer': 'Tavily API key not configured. Set TAVILY_API_KEY in .env.',
        'results': [],
      };
    }

    final client = TavilyClient();
    final response = await client.search(
      request: SearchRequest(
        apiKey: apiKey,
        query: args['query'] as String,
        maxResults: args['max_results'] as int? ?? 5,
        searchDepth: (args['search_depth'] as String?) == 'advanced'
            ? SearchRequestSearchDepth.advanced
            : SearchRequestSearchDepth.basic,
      ),
    );

    return {
      'answer': response.answer,
      'results': response.results
          .map((r) => {
                'title': r.title,
                'url': r.url,
                'content': r.content,
              })
          .toList(),
    };
  },
);

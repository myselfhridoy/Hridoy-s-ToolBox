import 'package:flutter/material.dart';
import '../core/storage/usage_store.dart';
import '../core/tokens.dart';

/// ⭐ বাটন — 48×48 টাচ টার্গেট, tooltip/screen-reader label সহ।
/// নিজেই UsageStore শোনে, তাই বাইরে rebuild লাগে না।
class FavoriteButton extends StatelessWidget {
  final String toolId;
  const FavoriteButton({super.key, required this.toolId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UsageStore.instance,
      builder: (context, _) {
        final fav = UsageStore.instance.isFavorite(toolId);
        return IconButton(
          tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
          iconSize: AppSizes.icon,
          icon: Icon(
            fav ? Icons.star : Icons.star_border,
            color: fav ? AppColors.star : AppColors.textSecondary,
          ),
          onPressed: () => UsageStore.instance.toggleFavorite(toolId),
        );
      },
    );
  }
}

import { LightningElement, api, track } from 'lwc';

export default class PerformanceLeaderboard extends LightningElement {
    @api entries = []; // Array of LeaderboardEntry from Apex: {rank, assigneeId, assigneeName, achievementPct, targetValue, actualValue, metric}

    get hasEntries() {
        return this.entries && this.entries.length > 0;
    }

    get formattedEntries() {
        return (this.entries || []).map(entry => ({
            ...entry,
            progressWidth: `width: ${Math.min(entry.achievementPct, 100)}%`,
            progressClass: this.getProgressClass(entry.achievementPct),
            badgeClass: this.getBadgeClass(entry.rank),
            displayPct: entry.achievementPct != null ? entry.achievementPct.toFixed(1) : '0.0',
            isTopThree: entry.rank <= 3,
            rankIcon: entry.rank === 1 ? '🥇' : entry.rank === 2 ? '🥈' : entry.rank === 3 ? '🥉' : '#' + entry.rank
        }));
    }

    getProgressClass(pct) {
        if (pct >= 100) return 'progress-bar achieved';
        if (pct >= 75) return 'progress-bar on-track';
        if (pct >= 50) return 'progress-bar at-risk';
        return 'progress-bar behind';
    }

    getBadgeClass(rank) {
        if (rank === 1) return 'rank-badge gold';
        if (rank === 2) return 'rank-badge silver';
        if (rank === 3) return 'rank-badge bronze';
        return 'rank-badge default';
    }
}
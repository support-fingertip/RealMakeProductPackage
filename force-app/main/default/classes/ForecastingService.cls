/**
 * @description Core forecasting engine for Real Estate Pre-Sales CRM.
 * Provides funnel analysis, reverse/forward forecasting, pipeline health,
 * source breakdown, and campaign ROI calculations.
 * Uses aggregate SOQL for performance with large data volumes.
 */
public with sharing class ForecastingService {

    // ═══════════════════════════════════════════════════════════════════
    //  INNER WRAPPER CLASSES
    // ═══════════════════════════════════════════════════════════════════

    public class ForecastFilter {
        @AuraEnabled public Id projectId;
        @AuraEnabled public String source;
        @AuraEnabled public String subSource;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public Id campaignId;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }

    public class FunnelStageResult {
        @AuraEnabled public String stageKey;
        @AuraEnabled public String stageLabel;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal cumulativeRate;
    }

    public class FunnelAnalysis {
        @AuraEnabled public List<FunnelStageResult> stages;
        @AuraEnabled public Map<String, Decimal> stageToStageRates;
        @AuraEnabled public Integer totalLeads;
        @AuraEnabled public Integer totalBookings;
        @AuraEnabled public Decimal overallConversionRate;
    }

    public class ReverseForecastResult {
        @AuraEnabled public String targetStage;
        @AuraEnabled public Integer targetCount;
        @AuraEnabled public List<FunnelStageResult> requiredAtEachStage;
    }

    public class ForwardForecastResult {
        @AuraEnabled public List<MonthlyForecast> monthlyForecasts;
        @AuraEnabled public Decimal leadVelocityRate;
        @AuraEnabled public Decimal avgSalesCycleDays;
    }

    public class MonthlyForecast {
        @AuraEnabled public String periodLabel;
        @AuraEnabled public Integer predictedLeads;
        @AuraEnabled public Integer predictedSiteVisits;
        @AuraEnabled public Integer predictedBookings;
        @AuraEnabled public Decimal predictedRevenue;
        @AuraEnabled public Decimal seasonalityIndex;
    }

    public class PipelineHealthResult {
        @AuraEnabled public Decimal healthScore;
        @AuraEnabled public String healthGrade;
        @AuraEnabled public List<HealthComponent> components;
    }

    public class HealthComponent {
        @AuraEnabled public String name;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public String status;
    }

    public class SourceBreakdown {
        @AuraEnabled public String source;
        @AuraEnabled public Integer leadCount;
        @AuraEnabled public Integer svCount;
        @AuraEnabled public Integer bookingCount;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal revenue;
    }

    public class CampaignROIResult {
        @AuraEnabled public Id campaignId;
        @AuraEnabled public String campaignName;
        @AuraEnabled public Decimal spend;
        @AuraEnabled public Integer leads;
        @AuraEnabled public Integer bookings;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Decimal roi;
        @AuraEnabled public Decimal costPerLead;
        @AuraEnabled public Decimal costPerBooking;
    }

    public class MonthlyTrendData {
        @AuraEnabled public String periodLabel;
        @AuraEnabled public Integer leads;
        @AuraEnabled public Integer siteVisits;
        @AuraEnabled public Integer bookings;
    }

    public class StageConversionDetail {
        @AuraEnabled public String fromStage;
        @AuraEnabled public String toStage;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Integer fromCount;
        @AuraEnabled public Integer toCount;
        @AuraEnabled public Integer dropOff;
    }

    public class ForecastDashboardData {
        @AuraEnabled public FunnelAnalysis funnel;
        @AuraEnabled public ForwardForecastResult forecast;
        @AuraEnabled public PipelineHealthResult health;
        @AuraEnabled public List<SourceBreakdown> sources;
        @AuraEnabled public List<CampaignROIResult> campaigns;
        @AuraEnabled public Decimal avgBookingValue;
        @AuraEnabled public List<MonthlyTrendData> monthlyTrend;
        @AuraEnabled public List<StageConversionDetail> conversionDetails;
    }

    public class FilterOptions {
        @AuraEnabled public List<OptionItem> projects;
        @AuraEnabled public List<OptionItem> sources;
        @AuraEnabled public List<OptionItem> owners;
    }

    public class OptionItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public OptionItem(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ForecastingException extends Exception {}

    // ═══════════════════════════════════════════════════════════════════
    //  CONFIG LOADER
    // ═══════════════════════════════════════════════════════════════════

    @TestVisible
    private static Forecast_Config__mdt getConfig() {
        List<Forecast_Config__mdt> configs = [
            SELECT Config_Key__c, Moving_Average_Months__c, Seasonality_Lookback_Months__c,
                   Funnel_Stages_JSON__c, Default_Forecast_Months__c, Health_Score_Weights_JSON__c,
                   Is_Active__c
            FROM Forecast_Config__mdt
            WHERE Config_Key__c = 'DEFAULT' AND Is_Active__c = true
            LIMIT 1
        ];
        if (!configs.isEmpty()) {
            return configs[0];
        }
        // Return defaults if no config record
        Forecast_Config__mdt cfg = new Forecast_Config__mdt();
        cfg.Moving_Average_Months__c = 3;
        cfg.Seasonality_Lookback_Months__c = 12;
        cfg.Default_Forecast_Months__c = 3;
        return cfg;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PUBLIC METHODS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Analyze the sales funnel with stage counts and conversion rates.
     */
    public static FunnelAnalysis analyzeFunnel(ForecastFilter filter) {
        FunnelAnalysis result = new FunnelAnalysis();
        result.stages = new List<FunnelStageResult>();
        result.stageToStageRates = new Map<String, Decimal>();

        // Stage 1: Total Leads (excluding Unqualified/Closed Lost)
        String leadWhere = buildLeadWhereClause(filter);
        String leadQuery = 'SELECT COUNT(Id) cnt FROM Lead__c WHERE Lead_Status__c NOT IN (\'Unqualified\', \'Closed Lost\')';
        if (String.isNotBlank(leadWhere)) {
            leadQuery += ' AND ' + leadWhere;
        }
        Integer totalLeads = getCountFromQuery(leadQuery);

        // Stage 2: SV Scheduled - COUNT_DISTINCT of Lead__c from Site_Visit__c
        String svWhere = buildChildWhereClause(filter, 'Lead__r.');
        String svScheduledQuery = 'SELECT COUNT_DISTINCT(Lead__c) cnt FROM Site_Visit__c WHERE Lead__c != null';
        if (String.isNotBlank(svWhere)) {
            svScheduledQuery += ' AND ' + svWhere;
        }
        Integer svScheduled = getCountFromQuery(svScheduledQuery);

        // Stage 3: SV Completed
        String svCompletedQuery = 'SELECT COUNT_DISTINCT(Lead__c) cnt FROM Site_Visit__c WHERE Lead__c != null AND Status__c = \'Completed\'';
        if (String.isNotBlank(svWhere)) {
            svCompletedQuery += ' AND ' + svWhere;
        }
        Integer svCompleted = getCountFromQuery(svCompletedQuery);

        // Stage 4: Cost Sheet
        String csWhere = buildChildWhereClause(filter, 'Lead__r.');
        String csQuery = 'SELECT COUNT_DISTINCT(Lead__c) cnt FROM Cost_Sheet__c WHERE Lead__c != null';
        if (String.isNotBlank(csWhere)) {
            csQuery += ' AND ' + csWhere;
        }
        Integer costSheets = getCountFromQuery(csQuery);

        // Stage 5: Booked (non-cancelled)
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');
        String bkQuery = 'SELECT COUNT_DISTINCT(Lead__c) cnt FROM Booking__c WHERE Lead__c != null AND Is_Cancelled__c = false';
        if (String.isNotBlank(bkWhere)) {
            bkQuery += ' AND ' + bkWhere;
        }
        Integer booked = getCountFromQuery(bkQuery);

        // Build stage results
        List<Integer> counts = new List<Integer>{ totalLeads, svScheduled, svCompleted, costSheets, booked };
        List<String> keys = new List<String>{ 'LEAD', 'SV_SCHEDULED', 'SV_COMPLETED', 'COST_SHEET', 'BOOKED' };
        List<String> labels = new List<String>{ 'New Enquiry', 'SV Scheduled', 'SV Completed', 'Cost Sheet', 'Booked' };

        for (Integer i = 0; i < counts.size(); i++) {
            FunnelStageResult stage = new FunnelStageResult();
            stage.stageKey = keys[i];
            stage.stageLabel = labels[i];
            stage.count = counts[i];
            stage.cumulativeRate = totalLeads > 0 ? (Decimal.valueOf(counts[i]) / totalLeads * 100).setScale(1) : 0;

            if (i > 0) {
                Decimal prevCount = counts[i - 1];
                stage.conversionRate = prevCount > 0 ? (Decimal.valueOf(counts[i]) / prevCount * 100).setScale(1) : 0;
                result.stageToStageRates.put(keys[i - 1] + '_TO_' + keys[i], stage.conversionRate);
            } else {
                stage.conversionRate = 100.0;
            }
            result.stages.add(stage);
        }

        result.totalLeads = totalLeads;
        result.totalBookings = booked;
        result.overallConversionRate = totalLeads > 0 ? (Decimal.valueOf(booked) / totalLeads * 100).setScale(2) : 0;

        return result;
    }

    /**
     * @description Reverse forecast: given a target count at a stage, compute upstream requirements.
     */
    public static ReverseForecastResult reverseForecast(String targetStage, Integer targetCount, ForecastFilter filter) {
        if (String.isBlank(targetStage)) {
            throw new ForecastingException('Target stage is required.');
        }
        if (targetCount == null || targetCount <= 0) {
            throw new ForecastingException('Target count must be a positive number.');
        }

        FunnelAnalysis funnel = analyzeFunnel(filter);

        ReverseForecastResult result = new ReverseForecastResult();
        result.targetStage = targetStage;
        result.targetCount = targetCount;
        result.requiredAtEachStage = new List<FunnelStageResult>();

        if (funnel == null || funnel.stages == null || funnel.stages.isEmpty()) {
            return result;
        }

        // Find target stage index
        Integer targetIdx = -1;
        Integer stageCount = funnel.stages.size();
        for (Integer i = 0; i < stageCount; i++) {
            if (funnel.stages[i].stageKey == targetStage) {
                targetIdx = i;
                break;
            }
        }
        if (targetIdx < 0) {
            throw new ForecastingException('Invalid target stage: ' + targetStage + '. Please select a valid stage.');
        }

        // Work backwards from target stage to calculate requirements
        Decimal required = Decimal.valueOf(targetCount);
        for (Integer i = targetIdx; i >= 0; i--) {
            FunnelStageResult stageReq = new FunnelStageResult();
            stageReq.stageKey = funnel.stages[i].stageKey;
            stageReq.stageLabel = funnel.stages[i].stageLabel;
            stageReq.count = (Integer) Math.ceil(required);

            if (i == targetIdx) {
                stageReq.conversionRate = 100.0;
            } else if (i + 1 < stageCount) {
                Decimal cr = funnel.stages[i + 1].conversionRate;
                stageReq.conversionRate = cr != null ? cr : 0;
            } else {
                stageReq.conversionRate = 0;
            }

            stageReq.cumulativeRate = funnel.stages[i].cumulativeRate;
            result.requiredAtEachStage.add(stageReq);

            // Calculate how many we need at previous stage
            if (i > 0 && i < stageCount) {
                Decimal cr = funnel.stages[i].conversionRate;
                if (cr != null && cr > 0) {
                    required = required / (cr / 100);
                } else {
                    // Use a default 10% conversion rate when no historical data
                    required = required / 0.10;
                }
                // Cap at a reasonable maximum to prevent overflow
                if (required > 999999999) {
                    required = 999999999;
                }
            }
        }

        // Reverse the list so stages go from earliest (Lead) to target stage
        List<FunnelStageResult> reversed = new List<FunnelStageResult>();
        for (Integer i = result.requiredAtEachStage.size() - 1; i >= 0; i--) {
            reversed.add(result.requiredAtEachStage[i]);
        }
        result.requiredAtEachStage = reversed;

        return result;
    }

    /**
     * @description Forward forecast using Weighted Moving Average with seasonality adjustment.
     */
    public static ForwardForecastResult forwardForecast(ForecastFilter filter, Integer months) {
        Forecast_Config__mdt config = getConfig();
        Integer windowSize = config.Moving_Average_Months__c != null
            ? Integer.valueOf(config.Moving_Average_Months__c) : 3;

        ForwardForecastResult result = new ForwardForecastResult();
        result.monthlyForecasts = new List<MonthlyForecast>();

        // Get historical monthly volumes
        Integer lookback = Math.max(windowSize + 3, 12);
        Map<String, Map<String, Integer>> monthlyData = getMonthlyVolumes(filter, lookback);

        List<Decimal> leadVolumes = new List<Decimal>();
        List<Decimal> svVolumes = new List<Decimal>();
        List<Decimal> bookingVolumes = new List<Decimal>();
        List<String> periodKeys = new List<String>(monthlyData.keySet());
        periodKeys.sort();

        for (String key : periodKeys) {
            Map<String, Integer> mData = monthlyData.get(key);
            leadVolumes.add(mData.containsKey('leads') ? mData.get('leads') : 0);
            svVolumes.add(mData.containsKey('siteVisits') ? mData.get('siteVisits') : 0);
            bookingVolumes.add(mData.containsKey('bookings') ? mData.get('bookings') : 0);
        }

        // Compute base predictions using WMA
        Decimal baseLeads = computeWeightedMovingAverage(leadVolumes, windowSize);
        Decimal baseSVs = computeWeightedMovingAverage(svVolumes, windowSize);
        Decimal baseBookings = computeWeightedMovingAverage(bookingVolumes, windowSize);

        // Compute growth rate from historical data
        Decimal leadGrowthRate = computeGrowthRate(leadVolumes);

        // Compute seasonality indices
        Map<Integer, Decimal> seasonality = computeSeasonalityIndices(filter);

        // Get average booking value
        Decimal avgBookingValue = getAverageBookingValue(filter);

        // Generate monthly projections
        Date today = Date.today();
        for (Integer i = 1; i <= months; i++) {
            Date futureMonth = today.addMonths(i);
            Integer monthNum = futureMonth.month();
            String periodLabel = getMonthLabel(futureMonth);

            Decimal seasonIdx = seasonality.containsKey(monthNum) ? seasonality.get(monthNum) : 1.0;
            Decimal growthMultiplier = Math.pow((1 + (leadGrowthRate / 100)).doubleValue(), i);

            MonthlyForecast mf = new MonthlyForecast();
            mf.periodLabel = periodLabel;
            mf.predictedLeads = (Integer) Math.round(baseLeads * seasonIdx * growthMultiplier);
            mf.predictedSiteVisits = (Integer) Math.round(baseSVs * seasonIdx * growthMultiplier);
            mf.predictedBookings = (Integer) Math.round(baseBookings * seasonIdx * growthMultiplier);
            mf.predictedRevenue = mf.predictedBookings * avgBookingValue;
            mf.seasonalityIndex = seasonIdx.setScale(2);
            result.monthlyForecasts.add(mf);
        }

        // Lead velocity rate
        result.leadVelocityRate = computeLeadVelocityRate(leadVolumes);

        // Average sales cycle
        result.avgSalesCycleDays = getAvgSalesCycleDays(filter);

        return result;
    }

    /**
     * @description Forward forecast for a specific target month/year.
     * Forecasts from today forward to the target month, but only returns the target month result.
     */
    public static ForwardForecastResult forwardForecastForMonth(ForecastFilter filter, Integer targetYear, Integer targetMonth) {
        Date today = Date.today();
        Date targetDate = Date.newInstance(targetYear, targetMonth, 1);

        // Calculate how many months ahead the target is
        Integer monthsAhead = ((targetYear - today.year()) * 12) + (targetMonth - today.month());
        if (monthsAhead < 1) {
            monthsAhead = 1;
        }

        // Use the existing forwardForecast to compute all months up to the target
        ForwardForecastResult fullResult = forwardForecast(filter, monthsAhead);

        // Return only the last month (the target month)
        ForwardForecastResult result = new ForwardForecastResult();
        result.monthlyForecasts = new List<MonthlyForecast>();
        if (!fullResult.monthlyForecasts.isEmpty()) {
            result.monthlyForecasts.add(fullResult.monthlyForecasts[fullResult.monthlyForecasts.size() - 1]);
        }
        result.leadVelocityRate = fullResult.leadVelocityRate;
        result.avgSalesCycleDays = fullResult.avgSalesCycleDays;

        return result;
    }

    /**
     * @description Compute pipeline health score (0-100) with grade.
     */
    public static PipelineHealthResult computePipelineHealth(ForecastFilter filter) {
        Forecast_Config__mdt config = getConfig();
        Map<String, Decimal> weights = new Map<String, Decimal>{
            'conversionRate' => 30, 'leadVelocity' => 25, 'funnelBalance' => 20,
            'noShowRate' => 15, 'cancellationRate' => 10
        };

        if (String.isNotBlank(config.Health_Score_Weights_JSON__c)) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(config.Health_Score_Weights_JSON__c);
            for (String key : parsed.keySet()) {
                weights.put(key, Decimal.valueOf(String.valueOf(parsed.get(key))));
            }
        }

        PipelineHealthResult result = new PipelineHealthResult();
        result.components = new List<HealthComponent>();

        FunnelAnalysis funnel = analyzeFunnel(filter);

        // 1. Conversion Rate Score (higher is better, benchmark 8-15%)
        Decimal crScore = Math.min(100, (funnel.overallConversionRate / 15) * 100);
        result.components.add(buildHealthComponent('Conversion Rate', crScore, weights.get('conversionRate')));

        // 2. Lead Velocity Score
        Map<String, Map<String, Integer>> monthlyData = getMonthlyVolumes(filter, 3);
        List<Decimal> recentLeads = new List<Decimal>();
        List<String> keys = new List<String>(monthlyData.keySet());
        keys.sort();
        for (String k : keys) {
            recentLeads.add(monthlyData.get(k).containsKey('leads') ? monthlyData.get(k).get('leads') : 0);
        }
        Decimal velocity = computeLeadVelocityRate(recentLeads);
        Decimal velocityScore = velocity >= 0 ? Math.min(100, 50 + velocity * 5) : Math.max(0, 50 + velocity * 5);
        result.components.add(buildHealthComponent('Lead Velocity', velocityScore, weights.get('leadVelocity')));

        // 3. Funnel Balance Score (are ratios healthy?)
        Decimal balanceScore = 100;
        if (funnel.stages.size() >= 5) {
            // Check if any stage has >0 leads but 0 at next stage
            for (Integer i = 1; i < funnel.stages.size(); i++) {
                if (funnel.stages[i - 1].count > 0 && funnel.stages[i].count == 0) {
                    balanceScore -= 25;
                }
            }
            balanceScore = Math.max(0, balanceScore);
        }
        result.components.add(buildHealthComponent('Funnel Balance', balanceScore, weights.get('funnelBalance')));

        // 4. No-Show Rate Score (lower is better)
        Decimal noShowRate = getNoShowRate(filter);
        Decimal noShowScore = Math.max(0, 100 - (noShowRate * 5));
        result.components.add(buildHealthComponent('SV No-Show Rate', noShowScore, weights.get('noShowRate')));

        // 5. Cancellation Rate Score (lower is better)
        Decimal cancRate = getCancellationRate(filter);
        Decimal cancScore = Math.max(0, 100 - (cancRate * 5));
        result.components.add(buildHealthComponent('Cancellation Rate', cancScore, weights.get('cancellationRate')));

        // Compute weighted total
        Decimal totalScore = 0;
        Decimal totalWeight = 0;
        for (HealthComponent comp : result.components) {
            totalScore += comp.score * comp.weight;
            totalWeight += comp.weight;
        }
        result.healthScore = totalWeight > 0 ? (totalScore / totalWeight).setScale(0) : 0;
        result.healthGrade = getGrade(result.healthScore);

        return result;
    }

    /**
     * @description Get source-wise funnel metrics.
     */
    public static List<SourceBreakdown> getSourceBreakdown(ForecastFilter filter) {
        List<SourceBreakdown> results = new List<SourceBreakdown>();

        String leadWhere = buildLeadWhereClause(filter);
        String sourceQuery = 'SELECT Lead_Source__c src, COUNT(Id) cnt FROM Lead__c WHERE Lead_Source__c != null AND Lead_Status__c NOT IN (\'Unqualified\', \'Closed Lost\')';
        if (String.isNotBlank(leadWhere)) {
            sourceQuery += ' AND ' + leadWhere;
        }
        sourceQuery += ' GROUP BY Lead_Source__c ORDER BY COUNT(Id) DESC';

        Map<String, Integer> leadsBySource = new Map<String, Integer>();
        for (AggregateResult ar : Database.query(sourceQuery)) {
            String src = (String) ar.get('src');
            Integer cnt = (Integer) ar.get('cnt');
            leadsBySource.put(src, cnt);
        }

        // Get bookings by source
        String bkSourceQuery = 'SELECT Lead__r.Lead_Source__c src, COUNT(Id) cnt, SUM(Grand_Total__c) rev FROM Booking__c WHERE Lead__c != null AND Is_Cancelled__c = false AND Lead__r.Lead_Source__c != null';
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');
        if (String.isNotBlank(bkWhere)) {
            bkSourceQuery += ' AND ' + bkWhere;
        }
        bkSourceQuery += ' GROUP BY Lead__r.Lead_Source__c';

        Map<String, Integer> bookingsBySource = new Map<String, Integer>();
        Map<String, Decimal> revenueBySource = new Map<String, Decimal>();
        for (AggregateResult ar : Database.query(bkSourceQuery)) {
            String src = (String) ar.get('src');
            bookingsBySource.put(src, (Integer) ar.get('cnt'));
            revenueBySource.put(src, ar.get('rev') != null ? (Decimal) ar.get('rev') : 0);
        }

        // Get site visits by source
        String svSourceQuery = 'SELECT Lead__r.Lead_Source__c src, COUNT(Id) cnt FROM Site_Visit__c WHERE Lead__c != null AND Lead__r.Lead_Source__c != null';
        String svWhere = buildChildWhereClause(filter, 'Lead__r.');
        if (String.isNotBlank(svWhere)) {
            svSourceQuery += ' AND ' + svWhere;
        }
        svSourceQuery += ' GROUP BY Lead__r.Lead_Source__c';

        Map<String, Integer> svsBySource = new Map<String, Integer>();
        for (AggregateResult ar : Database.query(svSourceQuery)) {
            String src = (String) ar.get('src');
            svsBySource.put(src, (Integer) ar.get('cnt'));
        }

        for (String source : leadsBySource.keySet()) {
            SourceBreakdown sb = new SourceBreakdown();
            sb.source = source;
            sb.leadCount = leadsBySource.get(source);
            sb.svCount = svsBySource.containsKey(source) ? svsBySource.get(source) : 0;
            sb.bookingCount = bookingsBySource.containsKey(source) ? bookingsBySource.get(source) : 0;
            sb.conversionRate = sb.leadCount > 0 ? (Decimal.valueOf(sb.bookingCount) / sb.leadCount * 100).setScale(1) : 0;
            sb.revenue = revenueBySource.containsKey(source) ? revenueBySource.get(source) : 0;
            results.add(sb);
        }

        return results;
    }

    /**
     * @description Compute campaign ROI metrics.
     */
    public static List<CampaignROIResult> getCampaignROI(ForecastFilter filter) {
        List<CampaignROIResult> results = new List<CampaignROIResult>();

        String campQuery = 'SELECT Id, Name, Campaign_Name__c, Actual_Spend__c FROM Campaign__c WHERE Status__c = \'Active\'';
        if (filter != null && filter.projectId != null) {
            campQuery += ' AND Target_Project__c = \'' + String.escapeSingleQuotes(filter.projectId) + '\'';
        }
        if (filter != null && filter.campaignId != null) {
            campQuery += ' AND Id = \'' + String.escapeSingleQuotes(filter.campaignId) + '\'';
        }
        campQuery += ' ORDER BY Actual_Spend__c DESC NULLS LAST LIMIT 20';

        List<Campaign__c> campaigns = Database.query(campQuery);
        if (campaigns.isEmpty()) {
            return results;
        }

        Set<Id> campIds = new Set<Id>();
        Map<Id, Campaign__c> campMap = new Map<Id, Campaign__c>();
        for (Campaign__c c : campaigns) {
            campIds.add(c.Id);
            campMap.put(c.Id, c);
        }

        // Count leads per campaign
        Map<Id, Integer> leadsByCamp = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Campaign__c camp, COUNT(Id) cnt
            FROM Lead__c
            WHERE Campaign__c IN :campIds
            GROUP BY Campaign__c
        ]) {
            leadsByCamp.put((Id) ar.get('camp'), (Integer) ar.get('cnt'));
        }

        // Count bookings + revenue per campaign
        Map<Id, Integer> bookingsByCamp = new Map<Id, Integer>();
        Map<Id, Decimal> revenueByCamp = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Lead__r.Campaign__c camp, COUNT(Id) cnt, SUM(Grand_Total__c) rev
            FROM Booking__c
            WHERE Lead__r.Campaign__c IN :campIds AND Is_Cancelled__c = false
            GROUP BY Lead__r.Campaign__c
        ]) {
            Id campId = (Id) ar.get('camp');
            bookingsByCamp.put(campId, (Integer) ar.get('cnt'));
            revenueByCamp.put(campId, ar.get('rev') != null ? (Decimal) ar.get('rev') : 0);
        }

        for (Campaign__c c : campaigns) {
            CampaignROIResult roi = new CampaignROIResult();
            roi.campaignId = c.Id;
            roi.campaignName = String.isNotBlank(c.Campaign_Name__c) ? c.Campaign_Name__c : c.Name;
            roi.spend = c.Actual_Spend__c != null ? c.Actual_Spend__c : 0;
            roi.leads = leadsByCamp.containsKey(c.Id) ? leadsByCamp.get(c.Id) : 0;
            roi.bookings = bookingsByCamp.containsKey(c.Id) ? bookingsByCamp.get(c.Id) : 0;
            roi.revenue = revenueByCamp.containsKey(c.Id) ? revenueByCamp.get(c.Id) : 0;
            roi.roi = roi.spend > 0 ? ((roi.revenue - roi.spend) / roi.spend * 100).setScale(1) : 0;
            roi.costPerLead = roi.leads > 0 ? (roi.spend / roi.leads).setScale(0) : 0;
            roi.costPerBooking = roi.bookings > 0 ? (roi.spend / roi.bookings).setScale(0) : 0;
            results.add(roi);
        }

        return results;
    }

    /**
     * @description Composite loader for dashboard — single Apex call.
     */
    public static ForecastDashboardData getDashboardData(ForecastFilter filter, Integer months) {
        ForecastDashboardData data = new ForecastDashboardData();
        data.funnel = analyzeFunnel(filter);
        data.forecast = forwardForecast(filter, months);
        data.health = computePipelineHealth(filter);
        data.sources = getSourceBreakdown(filter);
        data.campaigns = getCampaignROI(filter);
        data.avgBookingValue = getAverageBookingValue(filter);
        data.monthlyTrend = getMonthlyTrend(filter, 6);
        data.conversionDetails = getConversionDetails(data.funnel);
        return data;
    }

    /**
     * @description Get available filter options for the UI.
     */
    public static FilterOptions getFilterOptions() {
        FilterOptions opts = new FilterOptions();

        // Projects
        opts.projects = new List<OptionItem>();
        for (Project__c p : [SELECT Id, Name FROM Project__c WHERE Is_Active__c = true ORDER BY Name]) {
            opts.projects.add(new OptionItem(p.Name, p.Id));
        }

        // Sources
        opts.sources = new List<OptionItem>();
        for (AggregateResult ar : [
            SELECT Lead_Source__c src FROM Lead__c
            WHERE Lead_Source__c != null
            GROUP BY Lead_Source__c ORDER BY Lead_Source__c
        ]) {
            String src = (String) ar.get('src');
            opts.sources.add(new OptionItem(src, src));
        }

        // Owners — fetch active org users so the dropdown always has options
        opts.owners = new List<OptionItem>();
        for (User u : [
            SELECT Id, Name FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
            ORDER BY Name
            LIMIT 50
        ]) {
            opts.owners.add(new OptionItem(u.Name, u.Id));
        }

        return opts;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE METHODS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Build WHERE clause for Lead__c queries.
     */
    @TestVisible
    private static String buildLeadWhereClause(ForecastFilter filter) {
        if (filter == null) return '';
        List<String> conditions = new List<String>();

        if (filter.projectId != null) {
            conditions.add('Project__c = \'' + String.escapeSingleQuotes(filter.projectId) + '\'');
        }
        if (String.isNotBlank(filter.source)) {
            conditions.add('Lead_Source__c = \'' + String.escapeSingleQuotes(filter.source) + '\'');
        }
        if (String.isNotBlank(filter.subSource)) {
            conditions.add('Lead_Sub_Source__c = \'' + String.escapeSingleQuotes(filter.subSource) + '\'');
        }
        if (filter.ownerId != null) {
            conditions.add('Owner__c = \'' + String.escapeSingleQuotes(filter.ownerId) + '\'');
        }
        if (filter.campaignId != null) {
            conditions.add('Campaign__c = \'' + String.escapeSingleQuotes(filter.campaignId) + '\'');
        }
        if (filter.startDate != null) {
            conditions.add('CreatedDate >= ' + formatDate(filter.startDate));
        }
        if (filter.endDate != null) {
            conditions.add('CreatedDate <= ' + formatDate(filter.endDate.addDays(1)));
        }

        return String.join(conditions, ' AND ');
    }

    /**
     * @description Build WHERE clause for child object queries (Site_Visit__c, Booking__c, Cost_Sheet__c).
     */
    @TestVisible
    private static String buildChildWhereClause(ForecastFilter filter, String leadPrefix) {
        if (filter == null) return '';
        List<String> conditions = new List<String>();

        if (filter.projectId != null) {
            conditions.add(leadPrefix + 'Project__c = \'' + String.escapeSingleQuotes(filter.projectId) + '\'');
        }
        if (String.isNotBlank(filter.source)) {
            conditions.add(leadPrefix + 'Lead_Source__c = \'' + String.escapeSingleQuotes(filter.source) + '\'');
        }
        if (filter.ownerId != null) {
            conditions.add(leadPrefix + 'Owner__c = \'' + String.escapeSingleQuotes(filter.ownerId) + '\'');
        }
        if (filter.campaignId != null) {
            conditions.add(leadPrefix + 'Campaign__c = \'' + String.escapeSingleQuotes(filter.campaignId) + '\'');
        }
        if (filter.startDate != null) {
            conditions.add(leadPrefix + 'CreatedDate >= ' + formatDate(filter.startDate));
        }
        if (filter.endDate != null) {
            conditions.add(leadPrefix + 'CreatedDate <= ' + formatDate(filter.endDate.addDays(1)));
        }

        return String.join(conditions, ' AND ');
    }

    /**
     * @description Get monthly volumes for leads, site visits, and bookings.
     */
    @TestVisible
    private static Map<String, Map<String, Integer>> getMonthlyVolumes(ForecastFilter filter, Integer lookbackMonths) {
        Map<String, Map<String, Integer>> result = new Map<String, Map<String, Integer>>();

        Date startDate = Date.today().addMonths(-lookbackMonths);
        String dateFilter = 'CreatedDate >= ' + formatDate(startDate);

        // Leads by month
        String leadWhere = buildLeadWhereClause(filter);
        String leadQuery = 'SELECT CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate), COUNT(Id) cnt FROM Lead__c WHERE ' + dateFilter;
        if (String.isNotBlank(leadWhere)) {
            leadQuery += ' AND ' + leadWhere;
        }
        leadQuery += ' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate) ORDER BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)';

        for (AggregateResult ar : Database.query(leadQuery)) {
            String key = ar.get('expr0') + '-' + String.valueOf((Integer) ar.get('expr1')).leftPad(2, '0');
            if (!result.containsKey(key)) result.put(key, new Map<String, Integer>());
            result.get(key).put('leads', (Integer) ar.get('cnt'));
        }

        // Site visits by month
        String svWhere = buildChildWhereClause(filter, 'Lead__r.');
        String svQuery = 'SELECT CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate), COUNT(Id) cnt FROM Site_Visit__c WHERE ' + dateFilter;
        if (String.isNotBlank(svWhere)) {
            svQuery += ' AND ' + svWhere;
        }
        svQuery += ' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate) ORDER BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)';

        for (AggregateResult ar : Database.query(svQuery)) {
            String key = ar.get('expr0') + '-' + String.valueOf((Integer) ar.get('expr1')).leftPad(2, '0');
            if (!result.containsKey(key)) result.put(key, new Map<String, Integer>());
            result.get(key).put('siteVisits', (Integer) ar.get('cnt'));
        }

        // Bookings by month
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');
        String bkQuery = 'SELECT CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate), COUNT(Id) cnt FROM Booking__c WHERE Is_Cancelled__c = false AND ' + dateFilter;
        if (String.isNotBlank(bkWhere)) {
            bkQuery += ' AND ' + bkWhere;
        }
        bkQuery += ' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate) ORDER BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)';

        for (AggregateResult ar : Database.query(bkQuery)) {
            String key = ar.get('expr0') + '-' + String.valueOf((Integer) ar.get('expr1')).leftPad(2, '0');
            if (!result.containsKey(key)) result.put(key, new Map<String, Integer>());
            result.get(key).put('bookings', (Integer) ar.get('cnt'));
        }

        return result;
    }

    /**
     * @description Compute Weighted Moving Average.
     */
    @TestVisible
    private static Decimal computeWeightedMovingAverage(List<Decimal> values, Integer windowSize) {
        if (values == null || values.isEmpty()) return 0;

        Integer actualWindow = Math.min(windowSize, values.size());
        Decimal weightedSum = 0;
        Decimal weightTotal = 0;

        for (Integer i = 0; i < actualWindow; i++) {
            Integer idx = values.size() - actualWindow + i;
            Decimal weight = i + 1; // Most recent gets highest weight
            weightedSum += values[idx] * weight;
            weightTotal += weight;
        }

        return weightTotal > 0 ? (weightedSum / weightTotal).setScale(1) : 0;
    }

    /**
     * @description Compute seasonality indices by calendar month.
     */
    @TestVisible
    private static Map<Integer, Decimal> computeSeasonalityIndices(ForecastFilter filter) {
        Map<Integer, Decimal> indices = new Map<Integer, Decimal>();
        Map<Integer, List<Integer>> monthVolumes = new Map<Integer, List<Integer>>();

        Forecast_Config__mdt config = getConfig();
        Integer lookback = config.Seasonality_Lookback_Months__c != null
            ? Integer.valueOf(config.Seasonality_Lookback_Months__c) : 12;

        Map<String, Map<String, Integer>> monthly = getMonthlyVolumes(filter, lookback);

        Decimal totalAvg = 0;
        Integer totalCount = 0;

        for (String key : monthly.keySet()) {
            Integer mo = Integer.valueOf(key.split('-')[1]);
            Integer leads = monthly.get(key).containsKey('leads') ? monthly.get(key).get('leads') : 0;

            if (!monthVolumes.containsKey(mo)) {
                monthVolumes.put(mo, new List<Integer>());
            }
            monthVolumes.get(mo).add(leads);
            totalAvg += leads;
            totalCount++;
        }

        Decimal overallAvg = totalCount > 0 ? totalAvg / totalCount : 1;

        for (Integer mo = 1; mo <= 12; mo++) {
            if (monthVolumes.containsKey(mo)) {
                List<Integer> vols = monthVolumes.get(mo);
                Decimal sum = 0;
                for (Integer v : vols) sum += v;
                Decimal moAvg = vols.size() > 0 ? sum / vols.size() : 0;
                indices.put(mo, overallAvg > 0 ? (moAvg / overallAvg).setScale(2) : 1.0);
            } else {
                indices.put(mo, 1.0);
            }
        }

        return indices;
    }

    /**
     * @description Compute growth rate from historical data (slope-based).
     */
    private static Decimal computeGrowthRate(List<Decimal> values) {
        if (values == null || values.size() < 2) return 0;

        // Simple growth rate: compare last value to average of earlier values
        Decimal lastVal = values[values.size() - 1];
        Decimal prevVal = values[values.size() - 2];

        if (prevVal == 0) return 0;
        return ((lastVal - prevVal) / prevVal * 100).setScale(2);
    }

    /**
     * @description Compute Lead Velocity Rate.
     */
    private static Decimal computeLeadVelocityRate(List<Decimal> leadVolumes) {
        if (leadVolumes == null || leadVolumes.size() < 2) return 0;

        Decimal thisMonth = leadVolumes[leadVolumes.size() - 1];
        Decimal lastMonth = leadVolumes[leadVolumes.size() - 2];

        if (lastMonth == 0) return 0;
        return ((thisMonth - lastMonth) / lastMonth * 100).setScale(1);
    }

    /**
     * @description Get average sales cycle in days (Lead created to Booking date).
     */
    private static Decimal getAvgSalesCycleDays(ForecastFilter filter) {
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');

        String cycleQuery = 'SELECT Lead__r.CreatedDate, Booking_Date__c FROM Booking__c WHERE Lead__c != null AND Is_Cancelled__c = false AND Booking_Date__c != null';
        if (String.isNotBlank(bkWhere)) {
            cycleQuery += ' AND ' + bkWhere;
        }
        cycleQuery += ' LIMIT 500';

        Decimal totalDays = 0;
        Integer count = 0;
        for (Booking__c b : Database.query(cycleQuery)) {
            if (b.Lead__r.CreatedDate != null && b.Booking_Date__c != null) {
                Integer days = b.Lead__r.CreatedDate.date().daysBetween(b.Booking_Date__c);
                if (days >= 0) {
                    totalDays += days;
                    count++;
                }
            }
        }

        return count > 0 ? (totalDays / count).setScale(0) : 0;
    }

    /**
     * @description Get average booking value.
     */
    @TestVisible
    private static Decimal getAverageBookingValue(ForecastFilter filter) {
        String query = 'SELECT AVG(Grand_Total__c) avgVal FROM Booking__c WHERE Is_Cancelled__c = false AND Grand_Total__c > 0';
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');
        if (String.isNotBlank(bkWhere)) {
            query += ' AND ' + bkWhere;
        }

        List<AggregateResult> results = Database.query(query);
        if (!results.isEmpty() && results[0].get('avgVal') != null) {
            return ((Decimal) results[0].get('avgVal')).setScale(0);
        }
        return 0;
    }

    /**
     * @description Get site visit no-show rate.
     */
    private static Decimal getNoShowRate(ForecastFilter filter) {
        String svWhere = buildChildWhereClause(filter, 'Lead__r.');
        String scheduledQuery = 'SELECT COUNT(Id) cnt FROM Site_Visit__c WHERE Lead__c != null';
        if (String.isNotBlank(svWhere)) scheduledQuery += ' AND ' + svWhere;

        String noShowQuery = scheduledQuery + ' AND Status__c = \'No-Show\'';

        Integer scheduled = getCountFromQuery(scheduledQuery);
        Integer noShow = getCountFromQuery(noShowQuery);

        return scheduled > 0 ? (Decimal.valueOf(noShow) / scheduled * 100).setScale(1) : 0;
    }

    /**
     * @description Get booking cancellation rate.
     */
    private static Decimal getCancellationRate(ForecastFilter filter) {
        String bkWhere = buildChildWhereClause(filter, 'Lead__r.');
        String totalQuery = 'SELECT COUNT(Id) cnt FROM Booking__c WHERE Lead__c != null';
        if (String.isNotBlank(bkWhere)) totalQuery += ' AND ' + bkWhere;

        String cancelledQuery = totalQuery + ' AND Is_Cancelled__c = true';

        Integer total = getCountFromQuery(totalQuery);
        Integer cancelled = getCountFromQuery(cancelledQuery);

        return total > 0 ? (Decimal.valueOf(cancelled) / total * 100).setScale(1) : 0;
    }

    /**
     * @description Get monthly trend data for historical chart.
     */
    public static List<MonthlyTrendData> getMonthlyTrend(ForecastFilter filter, Integer lookbackMonths) {
        List<MonthlyTrendData> trend = new List<MonthlyTrendData>();
        Map<String, Map<String, Integer>> monthlyData = getMonthlyVolumes(filter, lookbackMonths);

        if (monthlyData.isEmpty()) {
            return trend;
        }

        List<String> periodKeys = new List<String>(monthlyData.keySet());
        periodKeys.sort();

        for (String key : periodKeys) {
            Map<String, Integer> mData = monthlyData.get(key);
            MonthlyTrendData mtd = new MonthlyTrendData();

            // Parse the key (YYYY-MM) to build a label
            List<String> parts = key.split('-');
            if (parts.size() == 2) {
                Integer yr = Integer.valueOf(parts[0]);
                Integer mo = Integer.valueOf(parts[1]);
                mtd.periodLabel = getMonthLabel(Date.newInstance(yr, mo, 1));
            } else {
                mtd.periodLabel = key;
            }

            mtd.leads = mData.containsKey('leads') ? mData.get('leads') : 0;
            mtd.siteVisits = mData.containsKey('siteVisits') ? mData.get('siteVisits') : 0;
            mtd.bookings = mData.containsKey('bookings') ? mData.get('bookings') : 0;
            trend.add(mtd);
        }

        return trend;
    }

    /**
     * @description Get stage-to-stage conversion details for conversion chart.
     */
    public static List<StageConversionDetail> getConversionDetails(FunnelAnalysis funnel) {
        List<StageConversionDetail> details = new List<StageConversionDetail>();

        if (funnel == null || funnel.stages == null || funnel.stages.size() < 2) {
            return details;
        }

        for (Integer i = 0; i < funnel.stages.size() - 1; i++) {
            FunnelStageResult fromStage = funnel.stages[i];
            FunnelStageResult toStage = funnel.stages[i + 1];

            StageConversionDetail detail = new StageConversionDetail();
            detail.fromStage = fromStage.stageKey;
            detail.toStage = toStage.stageKey;
            detail.label = fromStage.stageLabel + ' → ' + toStage.stageLabel;
            detail.rate = toStage.conversionRate != null ? toStage.conversionRate : 0;
            detail.fromCount = fromStage.count;
            detail.toCount = toStage.count;
            detail.dropOff = fromStage.count - toStage.count;
            details.add(detail);
        }

        return details;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UTILITY METHODS
    // ═══════════════════════════════════════════════════════════════════

    private static Integer getCountFromQuery(String query) {
        try {
            List<AggregateResult> results = Database.query(query);
            if (!results.isEmpty() && results[0].get('cnt') != null) {
                Object val = results[0].get('cnt');
                // COUNT_DISTINCT returns Long, COUNT returns Integer
                if (val instanceof Integer) {
                    return (Integer) val;
                }
                return Integer.valueOf(String.valueOf(val));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getCountFromQuery error: ' + e.getMessage() + ' | Query: ' + query);
        }
        return 0;
    }

    private static String formatDate(Date d) {
        return DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static String getMonthLabel(Date d) {
        List<String> months = new List<String>{
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        };
        return months[d.month() - 1] + ' ' + d.year();
    }

    private static String getGrade(Decimal score) {
        if (score >= 90) return 'A';
        if (score >= 80) return 'B';
        if (score >= 70) return 'C';
        if (score >= 60) return 'D';
        return 'F';
    }

    private static HealthComponent buildHealthComponent(String name, Decimal score, Decimal weight) {
        HealthComponent comp = new HealthComponent();
        comp.name = name;
        comp.score = score.setScale(0);
        comp.weight = weight;
        comp.status = score >= 70 ? 'Good' : (score >= 40 ? 'Warning' : 'Critical');
        return comp;
    }
}
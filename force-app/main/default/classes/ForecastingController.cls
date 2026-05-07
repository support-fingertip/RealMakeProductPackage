/**
 * @description Thin controller for the Sales Forecaster LWC.
 * Delegates all logic to ForecastingService. Follows Service-Controller pattern.
 */
public with sharing class ForecastingController {

    // ═══════════════════════════════════════════════════════════════════
    //  FILTER OPTIONS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get available filter options (projects, sources, owners).
     */
    @AuraEnabled(cacheable=true)
    public static ForecastingService.FilterOptions getFilterOptions() {
        try {
            return ForecastingService.getFilterOptions();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DASHBOARD DATA
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Composite loader for full dashboard data.
     * @param filterJson JSON string of ForecastFilter
     * @param forecastMonths Number of months to forecast forward
     */
    @AuraEnabled
    public static ForecastingService.ForecastDashboardData getDashboardData(String filterJson, Integer forecastMonths) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            Integer months = forecastMonths != null ? forecastMonths : 3;
            return ForecastingService.getDashboardData(filter, months);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  REVERSE FORECAST
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Compute reverse forecast — upstream requirements for a target.
     * @param targetStage The target funnel stage key (e.g., BOOKED)
     * @param targetCount Desired count at target stage
     * @param filterJson JSON string of ForecastFilter
     */
    @AuraEnabled
    public static ForecastingService.ReverseForecastResult getReverseForecast(String targetStage, Integer targetCount, String filterJson) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            return ForecastingService.reverseForecast(targetStage, targetCount, filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FORWARD FORECAST
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Compute forward forecast with WMA + seasonality.
     * @param filterJson JSON string of ForecastFilter
     * @param forecastMonths Number of months to project forward
     */
    @AuraEnabled
    public static ForecastingService.ForwardForecastResult getForwardForecast(String filterJson, Integer forecastMonths) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            Integer months = forecastMonths != null ? forecastMonths : 3;
            return ForecastingService.forwardForecast(filter, months);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FORWARD FORECAST — SPECIFIC MONTH
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Compute forward forecast for a specific target month/year.
     * @param filterJson JSON string of ForecastFilter
     * @param targetYear The target year (e.g. 2025)
     * @param targetMonth The target month (1-12)
     */
    @AuraEnabled
    public static ForecastingService.ForwardForecastResult getForwardForecastForMonth(String filterJson, Integer targetYear, Integer targetMonth) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            return ForecastingService.forwardForecastForMonth(filter, targetYear, targetMonth);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FUNNEL ANALYSIS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get funnel analysis with stage counts and conversion rates.
     * @param filterJson JSON string of ForecastFilter
     */
    @AuraEnabled
    public static ForecastingService.FunnelAnalysis getFunnelAnalysis(String filterJson) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            return ForecastingService.analyzeFunnel(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EXPORT — CSV
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Generate CSV export of forecast data.
     * @param filterJson JSON string of ForecastFilter
     * @param forecastMonths Number of months to forecast forward
     * @return CSV content as a string
     */
    @AuraEnabled
    public static String exportForecastCSV(String filterJson, Integer forecastMonths) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            Integer months = forecastMonths != null ? forecastMonths : 3;
            ForecastingService.ForecastDashboardData data = ForecastingService.getDashboardData(filter, months);

            List<String> csvLines = new List<String>();

            // Funnel Analysis Section
            csvLines.add('=== FUNNEL ANALYSIS ===');
            csvLines.add('Stage,Count,Conversion Rate (%),Cumulative Rate (%)');
            for (ForecastingService.FunnelStageResult s : data.funnel.stages) {
                csvLines.add(s.stageLabel + ',' + s.count + ',' + s.conversionRate + ',' + s.cumulativeRate);
            }
            csvLines.add('');

            // Forward Forecast Section
            csvLines.add('=== FORWARD FORECAST ===');
            csvLines.add('Month,Predicted Leads,Predicted Site Visits,Predicted Bookings,Predicted Revenue,Seasonality Index');
            for (ForecastingService.MonthlyForecast mf : data.forecast.monthlyForecasts) {
                csvLines.add(mf.periodLabel + ',' + mf.predictedLeads + ',' + mf.predictedSiteVisits + ',' +
                    mf.predictedBookings + ',' + mf.predictedRevenue + ',' + mf.seasonalityIndex);
            }
            csvLines.add('');

            // Pipeline Health Section
            csvLines.add('=== PIPELINE HEALTH ===');
            csvLines.add('Overall Score,' + data.health.healthScore);
            csvLines.add('Grade,' + data.health.healthGrade);
            csvLines.add('Component,Score,Weight,Status');
            for (ForecastingService.HealthComponent hc : data.health.components) {
                csvLines.add(hc.name + ',' + hc.score + ',' + hc.weight + ',' + hc.status);
            }
            csvLines.add('');

            // Source Breakdown Section
            csvLines.add('=== SOURCE BREAKDOWN ===');
            csvLines.add('Source,Leads,Site Visits,Bookings,Conversion Rate (%),Revenue');
            for (ForecastingService.SourceBreakdown sb : data.sources) {
                csvLines.add(sb.source + ',' + sb.leadCount + ',' + sb.svCount + ',' +
                    sb.bookingCount + ',' + sb.conversionRate + ',' + sb.revenue);
            }
            csvLines.add('');

            // Campaign ROI Section
            csvLines.add('=== CAMPAIGN ROI ===');
            csvLines.add('Campaign,Spend,Leads,Bookings,Revenue,ROI (%),Cost Per Lead,Cost Per Booking');
            for (ForecastingService.CampaignROIResult cr : data.campaigns) {
                csvLines.add(cr.campaignName + ',' + cr.spend + ',' + cr.leads + ',' +
                    cr.bookings + ',' + cr.revenue + ',' + cr.roi + ',' + cr.costPerLead + ',' + cr.costPerBooking);
            }

            return String.join(csvLines, '\n');
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EXPORT — PDF
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Generate PDF export of forecast data, saved as ContentVersion.
     * @param filterJson JSON string of ForecastFilter
     * @param forecastMonths Number of months to forecast forward
     * @return Download URL for the generated PDF
     */
    @AuraEnabled
    public static String exportForecastPDF(String filterJson, Integer forecastMonths) {
        try {
            ForecastingService.ForecastFilter filter = parseFilter(filterJson);
            Integer months = forecastMonths != null ? forecastMonths : 3;
            ForecastingService.ForecastDashboardData data = ForecastingService.getDashboardData(filter, months);

            // Build HTML for PDF
            String html = buildPdfHtml(data);

            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = 'Sales_Forecast_' + DateTime.now().format('yyyy-MM-dd_HHmm');
            cv.PathOnClient = cv.Title + '.html';
            cv.VersionData = Blob.valueOf(html);
            cv.Origin = 'C';
            insert cv;

            // Get ContentDocument ID
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

            return '/sfc/servlet.shepherd/document/download/' + cv.ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════════

    private static ForecastingService.ForecastFilter parseFilter(String filterJson) {
        if (String.isBlank(filterJson) || filterJson == '{}') {
            return new ForecastingService.ForecastFilter();
        }
        return (ForecastingService.ForecastFilter) JSON.deserialize(filterJson, ForecastingService.ForecastFilter.class);
    }

    private static String buildPdfHtml(ForecastingService.ForecastDashboardData data) {
        String html = '<html><head><style>';
        html += 'body{font-family:Arial,sans-serif;padding:24px;color:#333}';
        html += 'h1{color:#0a3055;border-bottom:2px solid #0ea5e9;padding-bottom:8px}';
        html += 'h2{color:#1e3a5f;margin-top:24px}';
        html += 'table{width:100%;border-collapse:collapse;margin:12px 0}';
        html += 'th{background:#0a3055;color:#fff;padding:8px 12px;text-align:left;font-size:12px}';
        html += 'td{padding:6px 12px;border-bottom:1px solid #e2e8f0;font-size:12px}';
        html += 'tr:nth-child(even){background:#f8fafc}';
        html += '.metric{display:inline-block;background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;padding:12px 20px;margin:4px;text-align:center}';
        html += '.metric-value{font-size:24px;font-weight:700;color:#0a3055}';
        html += '.metric-label{font-size:10px;color:#64748b;text-transform:uppercase}';
        html += '.grade{font-size:36px;font-weight:700;padding:4px 16px;border-radius:8px}';
        html += '.grade-A{background:#dcfce7;color:#16a34a}.grade-B{background:#dbeafe;color:#2563eb}';
        html += '.grade-C{background:#fef9c3;color:#ca8a04}.grade-D{background:#fed7aa;color:#ea580c}';
        html += '.grade-F{background:#fecaca;color:#dc2626}';
        html += '</style></head><body>';

        html += '<h1>Sales Forecast Report</h1>';
        html += '<p>Generated: ' + DateTime.now().format('dd MMM yyyy, hh:mm a') + '</p>';

        // Funnel Analysis
        html += '<h2>Funnel Analysis</h2>';
        html += '<div class="metric"><div class="metric-value">' + data.funnel.totalLeads + '</div><div class="metric-label">Total Leads</div></div>';
        html += '<div class="metric"><div class="metric-value">' + data.funnel.totalBookings + '</div><div class="metric-label">Bookings</div></div>';
        html += '<div class="metric"><div class="metric-value">' + data.funnel.overallConversionRate + '%</div><div class="metric-label">Conversion</div></div>';
        html += '<table><tr><th>Stage</th><th>Count</th><th>Stage CR</th><th>Cumulative</th></tr>';
        for (ForecastingService.FunnelStageResult s : data.funnel.stages) {
            html += '<tr><td>' + s.stageLabel + '</td><td>' + s.count + '</td><td>' + s.conversionRate + '%</td><td>' + s.cumulativeRate + '%</td></tr>';
        }
        html += '</table>';

        // Pipeline Health
        html += '<h2>Pipeline Health</h2>';
        html += '<div class="metric"><div class="grade grade-' + data.health.healthGrade + '">' + data.health.healthGrade + '</div><div class="metric-label">Score: ' + data.health.healthScore + '/100</div></div>';
        html += '<table><tr><th>Component</th><th>Score</th><th>Status</th></tr>';
        for (ForecastingService.HealthComponent hc : data.health.components) {
            html += '<tr><td>' + hc.name + '</td><td>' + hc.score + '</td><td>' + hc.status + '</td></tr>';
        }
        html += '</table>';

        // Forward Forecast
        html += '<h2>Forward Forecast</h2>';
        html += '<table><tr><th>Month</th><th>Leads</th><th>Site Visits</th><th>Bookings</th><th>Revenue</th><th>Seasonality</th></tr>';
        for (ForecastingService.MonthlyForecast mf : data.forecast.monthlyForecasts) {
            html += '<tr><td>' + mf.periodLabel + '</td><td>' + mf.predictedLeads + '</td><td>' + mf.predictedSiteVisits + '</td><td>' + mf.predictedBookings + '</td><td>' + formatCurrency(mf.predictedRevenue) + '</td><td>' + mf.seasonalityIndex + '</td></tr>';
        }
        html += '</table>';

        // Source Breakdown
        if (!data.sources.isEmpty()) {
            html += '<h2>Source Breakdown</h2>';
            html += '<table><tr><th>Source</th><th>Leads</th><th>Site Visits</th><th>Bookings</th><th>Conv %</th><th>Revenue</th></tr>';
            for (ForecastingService.SourceBreakdown sb : data.sources) {
                html += '<tr><td>' + sb.source + '</td><td>' + sb.leadCount + '</td><td>' + sb.svCount + '</td><td>' + sb.bookingCount + '</td><td>' + sb.conversionRate + '%</td><td>' + formatCurrency(sb.revenue) + '</td></tr>';
            }
            html += '</table>';
        }

        // Campaign ROI
        if (!data.campaigns.isEmpty()) {
            html += '<h2>Campaign ROI</h2>';
            html += '<table><tr><th>Campaign</th><th>Spend</th><th>Leads</th><th>Bookings</th><th>Revenue</th><th>ROI</th></tr>';
            for (ForecastingService.CampaignROIResult cr : data.campaigns) {
                html += '<tr><td>' + cr.campaignName + '</td><td>' + formatCurrency(cr.spend) + '</td><td>' + cr.leads + '</td><td>' + cr.bookings + '</td><td>' + formatCurrency(cr.revenue) + '</td><td>' + cr.roi + '%</td></tr>';
            }
            html += '</table>';
        }

        html += '</body></html>';
        return html;
    }

    private static String formatCurrency(Decimal value) {
        if (value == null) return '0';
        if (value >= 10000000) {
            return (value / 10000000).setScale(2) + ' Cr';
        }
        if (value >= 100000) {
            return (value / 100000).setScale(2) + ' L';
        }
        return String.valueOf(value.setScale(0));
    }
}
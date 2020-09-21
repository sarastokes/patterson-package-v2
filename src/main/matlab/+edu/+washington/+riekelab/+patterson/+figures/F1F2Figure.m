classdef F1F2Figure < symphonyui.core.FigureHandler
% F1F2FIGURE
%
% Description:
%   Generic figure for F1 amplitude/phase and optional F2 amplitude.
%
% History:
%   25Apr2017 - SSP
%   20Feb2019 - SSP - Cleaned up for new rigs
%   16Sep2020 - SSP - Improved analysis, added store data option
% -------------------------------------------------------------------------
   
    properties (SetAccess = private)
        device
        onlineAnalysis
        preTime
        stimTime
        
        temporalFrequency
        variedParameterName
        graphTitle
        waitTime
        showF2
        debug
    end

    properties (Access = private)
        axesHandle
        fitLine
        epochNum
        data

        debugData
    end
    
    properties (Hidden, Constant = true)
        BINRATE = 60
    end

    methods
        function obj = F1F2Figure(device, onlineAnalysis, preTime, stimTime, varargin)
            obj.device = device;
            obj.onlineAnalysis = onlineAnalysis;
            obj.preTime = preTime;
            obj.stimTime = stimTime;

            ip = inputParser();
            ip.CaseSensitive = false;
            addParameter(ip, 'TemporalFrequency', [], @isvector);
            addParameter(ip, 'WaitTime', 0, @isnumeric);
            addParameter(ip, 'ShowF2', false, @islogical);
            addParameter(ip, 'VariedParameterName', [], @ischar);
            addParameter(ip, 'GraphTitle', [], @ischar);
            addParameter(ip, 'Debug', 'none', @ischar);
            parse(ip, varargin{:});

            obj.temporalFrequency = ip.Results.TemporalFrequency;
            obj.waitTime = ip.Results.WaitTime;
            obj.showF2 = ip.Results.ShowF2;
            obj.variedParameterName = ip.Results.VariedParameterName;
            obj.graphTitle = ip.Results.GraphTitle;
            obj.debug = ip.Results.Debug;

            % Tracks epochs in case there is no varied parameter
            obj.epochNum = 0;

            if ~strcmp(obj.debug, 'none')
                dataDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\test\'];
                switch obj.debug
                    case 'contrast_spikes'
                        obj.debugData = dlmread([dataDir, 'demo_modulation_data.txt']);
                    case 'grating'
                        obj.debugData = dlmread([dataDir, 'demo_grating_data.txt']);
                    case 'bar_vclamp'
                        obj.debugData = dlmread([dataDir, 'demo_bar_vclamp_data.txt']);
                end
            end

            obj.createUi();
        end

        function createUi(obj)
            import appbox.*;

            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            storeDataButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Store Sweep', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedStoreData);
            setIconImage(storeDataButton, symphonyui.app.App.getResource('icons/sweep_store.png'));
            
            clearSweepButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Clear saved sweep', ...
                'Separator', 'off', ...
                'ClickedCallback', @obj.onSelectedClearStored);
            setIconImage(clearSweepButton,...
                symphonyui.app.App.getResource('icons', 'sweep_clear.png'));
            
            
            fitVonMisesButton = uipushtool( ...
                'Parent', toolbar, ...
                'TooltipString', 'Von Mises fit', ...
                'Separator', 'on', ...
                'ClickedCallback', @obj.onSelectedFitVonMises);
            setIconImage(fitVonMisesButton, [iconDir, 'VonMises.gif']);

            clearFitButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Clear Fit',...
                'ClickedCallback', @obj.onSelectedClearFit);
            setIconImage(clearFitButton,...
                symphonyui.app.App.getResource('icons', 'sweep_clear.png'));   
                
            
            captureFigureButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Save Picture',...
                'Separator', 'on',...
                'ClickedCallback', @obj.onSelectedCaptureFigure);
            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\icons\'];
            setIconImage(captureFigureButton, [iconDir, 'save_image.gif']);
              
            obj.axesHandle(1) = subplot(3,1,1:2,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto');
            
            obj.axesHandle(2) = subplot(3,1,3,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto', 'YLim', [-180 180], 'YTick', -180:90:180);

            set(obj.figureHandle, 'Color', 'w', 'Renderer', 'painters');
            
            ylabel(obj.axesHandle(1), 'spikes/sec');
            xlabel(obj.axesHandle(2), obj.variedParameterName);
            ylabel(obj.axesHandle(2), 'phase');

            if ~isempty(obj.graphTitle)
                obj.setTitle(obj.graphTitle);
            end
        end

        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle(1), t);
        end

        function clear(obj)
            cla(obj.axesHandle(1)); cla(obj.axesHandle(2));
            obj.data = []; obj.epochNum = 0;
        end

        function handleEpoch(obj, epoch)
            if ~epoch.hasResponse(obj.device)
                error(['Epoch does not contain a response for ' obj.device.name]);
            end
            
            obj.epochNum = obj.epochNum + 1;

            if strcmp(obj.variedParameterName, 'temporalFrequency')
                obj.temporalFrequency = epoch.parameters('temporalFrequency');
            end

            if isempty(obj.variedParameterName)
                xval = obj.epochNum;
            else
                xval = epoch.parameters(obj.variedParameterName);
            end

            if ~obj.debug
                response = epoch.getResponse(obj.device);
                quantities = response.getData();
                sampleRate = response.sampleRate.quantityInBaseUnits;
            else
                quantities = obj.debugData(obj.epochNum, :);
                sampleRate = 10000;
            end
            
            prePts = (obj.preTime+obj.waitTime) * 1e-3 * sampleRate;
            stimPts = obj.stimTime * 1e-3 * sampleRate;
            

            if strcmp(obj.onlineAnalysis, 'extracellular')
                res = edu.washington.riekelab.patterson.utils.spikeDetectorOnline(quantities, [], sampleRate);
                y = zeros(size(quantities));
                y(res.sp) = 1;
                y = edu.washington.riekelab.patterson.utils.binSpikeRate(...
                    y(prePts+1 : prePts + stimPts), obj.BINRATE, sampleRate);
            else
                y = quantities;
                if prePts > 0
                    y = y - median(y(1:prePts));
                else
                    y = y - median(y);
                end
                y = edu.washington.riekelab.patterson.utils.binData(...
                    y(prePts+1 : prePts+stimPts), obj.BINRATE, sampleRate);
            end
            
            cycleLength = obj.BINRATE / obj.temporalFrequency;
            numCycles = floor(length(y) / cycleLength);
            
            cycles = zeros(numCycles, floor(cycleLength));
            for i = 1:numCycles
                idx = round(((i - 1) * cycleLength + (1:floor(cycleLength))));
                cycles(i, :) = y(idx);
            end
            
            avgCycle = mean(cycles, 1);
          
            ft = fft(avgCycle);
            F0 = abs(ft(1)) / length(avgCycle) * 2;
            F1 = abs(ft(2)) / length(avgCycle) * 2;
            F2 = abs(ft(3)) / length(avgCycle) * 2;
            P1 = rad2deg(angle(ft(2)));
            P2 = rad2deg(angle(ft(3)));
            
            if isempty(obj.data)
                % Check for stored data
                storedData = obj.storedTable();
                if isempty(storedData)
                    obj.data = table(xval, F0, F1, F2, P1, P2,...
                        'VariableNames', {'X', 'F0', 'F1', 'F2', 'P1', 'P2'});
                else
                    obj.data = storedData;
                end
            else
                obj.data = [obj.data; {xval, F0, F1, F2, P1, P2}];
                obj.data = sortrows(obj.data, 'X', 'ascend');
            end

            cla(obj.axesHandle(1)); cla(obj.axesHandle(2));

            % Plot the raw data (just for F1...)
            line(obj.data.X, obj.data.F1,...
                'Parent', obj.axesHandle(1),...
                'Marker', 'x', 'MarkerSize', 5, 'Color', [0.5, 0.5, 0.5],...
                'LineWidth', 1, 'LineStyle', 'none',...
                'DisplayName', 'F1 Data');
            line(obj.data.X, obj.data.P1,...
                'Parent', obj.axesHandle(2),...
                'Marker', 'x', 'MarkerSize', 5, 'Color', [0.5, 0.5, 0.5],...
                'LineWidth', 1, 'LineStyle', 'none');
                
            % Plot the averages
            [G, groupNames] = findgroups(obj.data.X);
            if obj.showF2
                line(groupNames, splitapply(@mean, obj.data.F2, G),...
                    'Parent', obj.axesHandle(1),...
                    'Marker', 'o', 'Color', [1, 0.34, 0.34],... 
                    'LineWidth', 1.5, 'MarkerFaceColor', [1, 0.82, 0.82],...
                    'DisplayName', 'F2 Avg');
                line(groupNames, splitapply(@mean, obj.data.P2, G),...
                    'Parent', obj.axesHandle(2),...
                    'Marker', 'o', 'Color', [1, 0.34, 0.34],...
                    'LineWidth', 1.5, 'MarkerFaceColor', [1, 0.82, 0.82],...
                    'DisplayName', 'F2');
            end
            line(groupNames, splitapply(@mean, obj.data.F1, G),...
                'Parent', obj.axesHandle(1),...
                'Marker', 'o', 'Color', [0.54, 0.6, 1],... 
                'LineWidth', 1.5, 'MarkerFaceColor', [0.77, 0.8, 1],...
                'DisplayName', 'F1 Avg');
            
            line(groupNames, splitapply(@mean, obj.data.P1, G),...
                'Parent', obj.axesHandle(2),...
                'Marker', 'o', 'Color', [0.54, 0.6, 1],... 
                'LineWidth', 1.5, 'MarkerFaceColor', [0.77, 0.8, 1]);
            
            % legend(obj.axesHandle(1), 'FontSize', 7,... 
            %     'Location', 'southoutside', 'Orientation', 'horizontal');
        end
    end

    methods (Access = private)
        function onSelectedFitVonMises(obj, ~, ~)
            % TODO: Use mean or raw data?
            [G, directions] = findgroups(obj.data.X);
            avgMag =  splitapply(@mean, obj.data.F1, G);

            offsetFactor = min(avgMag);
            [scaleFactor, idx] = max(avgMag - offsetFactor);
            magNorm = (avgMag - offsetFactor) / scaleFactor;

            out = edu.washington.riekelab.patterson.utils.VonMises(...
                'X', directions, 'Y', magNorm,...
                'mu', directions(idx));
            
            dsi = edu.washington.riekelab.patterson.utils.getDsiOsi(...
                directions, avgMag);
            
            title(obj.axesHandle, sprintf('%u +- %.2f (dsi = %.2f)',... 
                    round(out.mu), round(out.hwhh), round(dsi, 2)));

            smoothFit = out.yFitSmooth * scaleFactor + offsetFactor;
            if isempty(obj.fitLine)
                obj.fitLine = line(out.xSmooth, smoothFit,...
                    'Parent', obj.axesHandle,...
                    'Color', [0.51, 0, 0], 'LineWidth', 1.5);
            else
                set(obj.fitLine, 'XData', out.xSmooth, 'YData', smoothFit);
            end
        end
        
        function onSelectedClearFit(obj, ~, ~)
            if ~isempty(obj.fitLine)
                if isvalid(obj.fitLine)
                    delete(obj.fitLine);
                end
                obj.fitLine = [];
            end
            obj.setTitle(obj.graphTitle);
        end
        
        function onSelectedStoreData(obj, ~, ~)
            obj.storedTable('Clear');
            obj.storedTable(obj.data);
            set(findall(obj.figureHandle, 'Marker', 'o'), 'Color', [0.5, 0, 0]);
        end

        function onSelectedClearStored(obj, ~, ~)
            obj.storedTable('Clear');
        end
        
        function onSelectedCaptureFigure(obj, ~, ~)
            [fileName, pathName] = uiputfile('grating.png', 'Save result as');
            if ~ischar(fileName) || ~ischar(pathName)
                return;
            end
            print(obj.figureHandle, [pathName, fileName], '-dpng', '-r600');
        end
    end
    
    methods (Static)
        function data = storedTable(data)
            persistent stored;
            if nargin == 0  % retrieve stored data
                data = stored;
            else  % set of clear stored data
                if strcmp(data, 'Clear')
                    stored = [];
                else
                    stored = data;
                    data = stored;
                end
            end
        end
    end
end
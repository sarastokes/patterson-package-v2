classdef DirectionSelectivityFigure < symphonyui.core.FigureHandler
% DIRECTIONSELECTIVITYFIGURE
%
% Description:
%   Response magnitude as a function of direction with option for storing
%   data, computing DSI and Von Mises fit
%
% History:
%   19Sep2020 - SSP
% -------------------------------------------------------------------------

    properties (SetAccess = private)
        device
        preTime 
        stimTime 
        onlineAnalysis
        
        debug 
        graphTitle
    end

    properties (Access = private)
        axesHandle
        rawLine
        avgLine
        fitLine
        data

        epochNum
        debugData
    end

    methods 
        function obj = DirectionSelectivityFigure(device, onlineAnalysis, preTime, stimTime, varargin)
            obj.device = device;
            obj.onlineAnalysis = onlineAnalysis;
            obj.preTime = preTime;
            obj.stimTime = stimTime;
            
            ip = inputParser();
            ip.CaseSensitive = false;
            addParameter(ip, 'GraphTitle', 'Direction Selectivity', @ischar);
            addParameter(ip, 'Debug', false, @islogical);
            parse(ip, varargin{:});
            
            obj.epochNum = 0;

            obj.graphTitle = ip.Results.GraphTitle;
            obj.debug = ip.Results.Debug;

            if obj.debug
                dataDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\test\'];
                obj.debugData = dlmread([dataDir, 'demo_bar_data.txt']);
            end

            obj.createUi();
        end

        function createUi(obj)
            import appbox.*;

            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\icons\'];

            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            storeDataButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Store Data',...
                'Separator', 'on',...
                'ClickedCallback', @obj.onSelectedStoreData);
            setIconImage(storeDataButton,... 
                symphonyui.app.App.getResource('icons', 'sweep_store.png'));

            clearDataButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Clear Data',...
                'ClickedCallback', @obj.onSelectedClearData);
            setIconImage(clearDataButton,...
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
                'TooltipString', 'Store Sweep',...
                'Separator', 'on',...
                'ClickedCallback', @obj.onSelectedCaptureFigure);
            setIconImage(captureFigureButton, [iconDir, 'save_image.gif']);

            obj.axesHandle = axes(...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultUicontrolFontSize'),...
                'XTickMode', 'auto', 'XLim', [0, 360]);
            
            xlabel(obj.axesHandle, 'direction (degrees)');
            if strcmp(obj.onlineAnalysis, 'extracellular')
                ylabel(obj.axesHandle, 'spike count');  
            else
                ylabel(obj.axesHandle, 'charge transfer (pC)');
            end
           
            set(obj.figureHandle, 'Color', 'w', 'Renderer', 'painters');
            obj.setTitle(obj.graphTitle);
        end
        
        function setTitle(obj, t)
            set(obj.figureHandle, 'Name', t);
            title(obj.axesHandle, t);
        end

        function clear(obj)
            cla(obj.axesHandle);
            obj.data = [];
            obj.epochNum = 0;
            obj.fitLine = []; obj.rawLine = []; obj.avgLine = [];
        end

        function handleEpoch(obj, epoch)
            obj.epochNum = obj.epochNum + 1;

            if ~obj.debug
                response = epoch.getResponse(obj.device);
                quantities = response.getData();
                sampleRate = response.sampleRate.quantityInBaseUnits;
            else
                quantities = obj.debugData(obj.epochNum, :);
                sampleRate = 10000;
            end
            
            direction = epoch.parameters('direction');

            prePts = obj.preTime * 1e-3 * sampleRate;
            stimPts = obj.stimTime * 1e-3 * sampleRate;

            % Analysis
            if strcmp(obj.onlineAnalysis, 'extracellular')
                results = edu.washington.riekelab.patterson.utils.spikeDetectorOnline(quantities, [], sampleRate);
                y = zeros(size(quantities));
                y(results.sp) = 1;
                responseMagnitude = sum(y(prePts+1 : prePts+stimPts));

            else % voltage clamp
                y = quantities - mean(quantities(1:prePts));
                y = y(prePts+1 : prePts+stimPts);
                
                if strcmp(obj.onlineAnalysis, 'exc')
                    chargeMult = -1;
                elseif strcmp(obj.onlineAnalysis, 'inh')
                    chargeMult = 1;
                end

                y = chargeMult * trapz(y);
                responseMagnitude = y / sampleRate;
            end
            
            if isempty(obj.data)
                % Check for stored data
                storedData = obj.storedTable();
                if isempty(storedData)
                    obj.data = table(direction, responseMagnitude,...
                        'VariableNames', {'X', 'Magnitude'});
                else
                    obj.data = storedData;
                end
            else
                obj.data = [obj.data; {direction, responseMagnitude}];
                obj.data = sortrows(obj.data, 'X', 'ascend');
            end

            if isempty(obj.rawLine)
                obj.rawLine = line(obj.data.X, obj.data.Magnitude,...
                    'Parent', obj.axesHandle,...
                    'Marker', 'x', 'MarkerSize', 5,... 
                    'Color', [0.5, 0.5, 0.5],...
                    'LineWidth', 1, 'LineStyle', 'none');
            else
                set(obj.rawLine,...
                    'XData', obj.data.X, 'YData', obj.data.Magnitude);
            end
            
            % Average data
            [G, groupNames] = findgroups(obj.data.X);
            avgMag = splitapply(@mean, obj.data.Magnitude, G);
            if isempty(obj.avgLine)
                obj.avgLine = line(groupNames, avgMag,...
                    'Parent', obj.axesHandle,...
                    'Marker', 'o', 'MarkerSize', 7,... 
                    'LineWidth', 1.5, 'Color', [0.54, 0.6, 1],... 
                    'MarkerFaceColor', [0.77, 0.8, 1]);
            else
                set(obj.avgLine,...
                    'XData', groupNames, 'YData', avgMag);
            end
            
            axis(obj.axesHandle, 'tight');
            set(obj.axesHandle, 'XLim', [-10, 370], 'XTick', 0:60:360);
            obj.axesHandle.YLim(1) = 0;
        end
    end

    methods (Access = private)
        function onSelectedFitVonMises(obj, ~, ~)
            % TODO: Use mean or raw data?
            [G, directions] = findgroups(obj.data.X);
            avgMag =  splitapply(@mean, obj.data.Magnitude, G);

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
            set(obj.avgLine, 'LineStyle', 'none');
        end

        function onSelectedClearFit(obj, ~, ~)
            if ~isempty(obj.fitLine)
                if isvalid(obj.fitLine)
                    delete(obj.fitLine);
                end
                obj.fitLine = [];
            end
            if ~isempty(obj.avgLine)
                if isvalid(obj.avgLine)
                    set(obj.avgLine, 'LineStyle', '-');
                end
            end
            obj.setTitle(obj.graphTitle);
        end

        function onSelectedStoreData(obj, ~, ~)
            obj.storedTable('Clear');
            obj.storedTable(obj.data);
            set(findall(obj.figureHandle, 'Marker', 'o'), 'Color', [0.5, 0, 0]);
        end

        function onSelectedClearData(obj, ~, ~)
            obj.storedTable('Clear');
        end
        
        function onSelectedCaptureFigure(obj, ~, ~)
            [fileName, pathName] = uiputfile('direction_selectivity.png', 'Save result as');
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
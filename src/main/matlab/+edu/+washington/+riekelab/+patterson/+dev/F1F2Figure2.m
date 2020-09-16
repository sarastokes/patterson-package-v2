classdef F1F2Figure2 < symphonyui.core.FigureHandler
   
    properties (SetAccess = private)
        device
        onlineAnalysis
        preTime
        stimTime
        
        temporalFrequency
        variedParameterName
        waitTime
        showF2
    end

    properties (Hidden, Access = private)
        axesHandle
        lineHandle
        dataTable
    end
    
    properties (Hidden, Constant = true)
        BINRATE = 60
    end

    methods
        function obj = F1F2Figure2(device, onlineAnalysis, preTime, stimTime, varargin)
            obj.device = device;
            obj.onlineAnalysis = onlineAnalysis;
            obj.preTime = preTime;
            obj.stimTime = stimTime;

            ip = inputParser();
            addParameter(ip, 'TemporalFrequency', [], @isvector);
            addParameter(ip, 'WaitTime', 0, @isnumeric);
            addParameter(ip, 'ShowF2', false, @islogical);
            addParameter(ip, 'VariedParameterName', [], @ischar);
            addParameter(ip, 'GraphTitle', [], @ischar);
            parse(ip, varargin{:});

            obj.temporalFrequency = ip.Results.temporalFrequency;
            obj.waitTime = ip.Results.WaitTime;
            obj.showF2 = ip.Results.ShowF2;
            obj.variedParameterName = ip.Results.VariedParameterName;
            obj.graphTitle = ip.Results.graphTitle;

            % Tracks epochs in case there is no varied parameter
            obj.epochNum = 0;

            obj.createUi();
        end

        function createUi(obj)
            import appbox.*;

            toolbar = findall(obj.figureHandle, 'Type', 'uitoolbar');
            captureFigureButton = uipushtool(...
                'Parent', toolbar,...
                'TooltipString', 'Save Picture',...
                'Separator', 'on',...
                'ClickedCallback', @obj.onSelectedCaptureFigure);
            iconDir = [fileparts(fileparts(mfilename('fullpath'))), '\+icons\'];
            setIconImage(captureFigureButton, [iconDir, 'save_image.png']);
              
            obj.axesHandle(1) = subplot(3,1,1:2,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto');
            
            obj.axesHandle(2) = subplot(3,1,3,...
                'Parent', obj.figureHandle,...
                'FontName', get(obj.figureHandle, 'DefaultUicontrolFontName'),...
                'FontSize', get(obj.figureHandle, 'DefaultLegendFontSize'),...
                'XTickMode', 'auto');

            set(obj.figureHandle, 'Color', 'w');
            
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

            response = epoch.getResponse(obj.device);
            quantities = response.getData();
            sampleRate = response.sampleRate.quantityInBaseUnits;
            
            prePts = (obj.preTime+obj.waitTime) * 1e-3 * sampleRate;
            stimFrames = obj.stimTime * 1e-3 * obj.BINRATE;

            y = quantities;
            if strcmp(obj.onlineAnalysis, 'extracellular')
                res = edu.washington.riekelab.patterson.utils.spikeDetectorOnline(y, [], sampleRate);
                y = zeros(size(y));
                y(res.sp) = 1;
                y = edu.washington.riekelab.patterson.utils.binSpikeRate(...
                    y(prePts+1:end), obj.BINRATE, sampleRate);
            else
                if prePts > 0
                    y = y - median(y(1:prePts));
                else
                    y = y - median(y);
                end
                y = edu.washington.riekelab.patterson.utils.binData(...
                    y(prePts+1:end), obj.BINRATE, sampleRate);
            end

            binSize = obj.BINRATE / obj.temporalFrequency;
            numBins = floor(stimFrames/binSize);
            avgCycle = zeros(1, floor(binSize));
            for k = 1:numBins
                index = round((k-1)*binSize) + (1:floor(binSize));
                index(index > length(y)) = [];
                ytmp = y(index);
                avgCycle = avgCycle + ytmp(:)';
            end
            avgCycle = avgCycle / numBins;

            ft = fft(avgCycle);
            F1 = abs(ft(2)) / length(avgCycle) * 2;
            F2 = abs(ft(3)) / length(avgCycle) * 2;
            P1 = angle(ft(2));
            
            if isempty(obj.data)
                obj.data = table({xval, F1, F2, P1},...
                    'VariableNames', {'X', 'F1', 'F2', 'P1'});
            else
                obj.data = [obj.data; {xval, F1, F2, P1}];
                obj.data = sortrows(obj.data, 'ascend', 'xval');
            end

            cla(obj.axesHandle(1)); cla(obj.axesHandle(2));

            % Plot the raw data - TODO add to existing plots
            line(obj.data.X, obj.data.F1,...
                'Parent', obj.axesHandle(1),...
                'Marker', 'o', 'Color', [0.5, 0.5, 0.5],...
                'LineStyle', 'none');
            if obj.showF2
                line(obj.data.X, obj.data.F2,...
                    'Parent', obj.axesHandle(1),...
                    'Marker', 'o', 'Color', [0.5, 0.5, 1],... 
                    'LineStyle', 'none');
            end
            line(obj.data.X, obj.data.P1,...
                'Parent', obj.axesHandle(2),...
                'Marker', 'o', 'Color', [0.5, 0.5, 0.5],...
                'LineStyle', 'none');
                
            % Plot the averages
            [G, groupNames] = findgroups(obj.data.X);
            line(obj.data.X, splitapply(@mean, obj.data.F1, G),...
                'Parent', obj.axesHandle(1),...
                'Marker', 'o', 'Color', 'k', 'LineWidth', 1.25);
            if obj.showF2
                line(obj.data.X, splitapply(@mean, obj.data.F2, G),...
                    'Parent', obj.axesHandle(1),...
                    'Marker', 'o', 'Color', 'b', 'LineWidth', 1.25);
            end
            line(obj.data.X, splitapply(@mean, obj.data.P1, G),...
                'Parent', obj.axesHandle(2),...
                'Marker', 'o', 'Color', 'k', 'LineWidth', 1.25);               

        end
    end

    methods (Access = private)
        function onSelectedCaptureFigure(obj, ~, ~)
            [fileName, pathName] = uiputfile('grating.png', 'Save result as');
            if ~ischar(fileName) || ~ischar(pathName)
                return;
            end
            print(obj.figureHandle, [pathName, fileName], '-dpng', '-r600');
        end
    end
    
end
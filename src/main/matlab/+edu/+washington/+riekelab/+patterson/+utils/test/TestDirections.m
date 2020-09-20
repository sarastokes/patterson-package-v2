classdef TestDirections < edu.washington.riekelab.protocols.RiekeLabProtocol

    properties 
        led 
        preTime = 500
        stimTime = 1250
        tailTime = 500
        speed = 600
        backgroundIntensity = 0.5
        contrast = 1
        directions = 0:30:330
        onlineAnalysis = 'none'
        numberOfAverages = uint16(36)
        interpulseInterval = 0
        amp 
    end

    properties (Hidden)
        ledType 
        ampType 
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'exc', 'inh'})

        epochNum
        direction 
        allDirections
    end

    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);

            % Input validation
            if rem(obj.numberOfAverages, numel(obj.directions)) ~= 0
                error('numberOfAverages is not a factor of directions');
            end
            
            dataDir = [fileparts(fileparts(mfilename('fullpath'))), '\+utils\test\'];
            obj.allDirections = dlmread([dataDir, 'demo_bar_directions.txt']);
            obj.epochNum = 0;

            % Set analysis figures
            rgb = edu.washington.riekelab.patterson.utils.multigradient(...
                'preset', 'div.cb.spectral.9',... 
                'length', numel(unique(obj.directions)));

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure',...
                obj.rig.getDevice(obj.amp));
            obj.showFigure('edu.washington.riekelab.patterson.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp), 'groupBy', {'direction'},...
                'recordingType', obj.onlineAnalysis, 'sweepColor', rgb);
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('edu.washington.riekelab.patterson.figures.DirectionSelectivityFigure',...
                    obj.rig.getDevice(obj.amp), obj.onlineAnalysis,...
                    obj.preTime, obj.stimTime, 'Debug', true);
            end

            device = obj.rig.getDevice(obj.led);
            device.background = symphonyui.core.Measurement(...
                obj.backgroundIntensity, device.background.displayUnits);
        end

        function stim = createLedStimulus(obj)

            gen = symphonyui.builtin.stimuli.PulseGenerator();
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.mean = obj.backgroundIntensity;
            gen.amplitude = obj.backgroundIntensity * obj.contrast + obj.backgroundIntensity;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;

            stim = gen.generate();
        end

        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            obj.epochNum = obj.epochNum + 1;
            
            obj.direction = obj.allDirections(obj.epochNum);
            epoch.addParameter('direction', obj.direction);

            epoch.addStimulus(obj.rig.getDevice(obj.led),... 
                obj.createLedStimulus());
            epoch.addResponse(obj.rig.getDevice(obj.amp));

        end

        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
            interval.addDirectCurrentStimulus(device,...
                device.background, obj.interpulseInterval, obj.sampleRate);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end 
    end
end 
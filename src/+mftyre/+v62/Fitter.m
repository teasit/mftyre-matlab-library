classdef Fitter < handle
    %MFTYRE.V62.FITTER Fits MF-Tyre models to measurement data.
    properties
        %Set the measurements to be used for fitting.
        Measurements tydex.Measurement
        
        %Set the initial parameter to be used for fitting.
        Parameters mftyre.v62.Parameters
        
        %Set the Fit-Modes to execute when using run() method.
        FitModes mftyre.v62.FitMode
        
        %Solver options. Set max iterations, function evaluations etc.
        Options optim.options.SolverOptions = optimoptions('fmincon', ...
            'Display', 'iter-detailed')
    end
    properties (SetAccess = protected)
        %Fitted parameter values, updated after each Fit-Mode solve.
        ParametersFitted mftyre.v62.Parameters
    end
    properties (SetAccess = protected, Transient)
        %Returns the Fit-Mode that is currently being solved.
        %In case the "OutputFcn" property in the Fitter options is used,
        %the user can make use of the ActiveFitMode property to print the
        %current equation being fitted, for example.
        ActiveFitMode mftyre.v62.FitMode
    end
    properties (Access = private)
        FitModeFlags containers.Map
    end
    methods
        function set.FitModes(fitter, fitmodes)
            fitmodes = unique(fitmodes);
            fitmodes = sort(fitmodes);
            fitter.FitModes = fitmodes;
        end
        function set.Measurements(fitter, measurements)
            fitter.Measurements = measurements;
            if isempty(measurements)
                return
            end
            fitter.qualifyMeasurements()
        end
    end
    methods
        function x = solve(fitter,fitmode)
            %SOLVE Fit model only for one fitmode.
            arguments
                fitter  mftyre.v62.Fitter
                fitmode mftyre.v62.FitMode
            end
            import('mftyre.v62.FitMode')
            fitter.ActiveFitMode = fitmode;
            
            idx = fitter.FitModeFlags(char(fitmode));
            meas = fitter.Measurements(idx);
            params = fitter.Parameters;
            meas = downsample(meas,3,0);
            mfinputs = fitter.preprocess(meas);
            
            switch fitmode
                case {FitMode.Fx0, FitMode.Fx}
                    testdata = cat(1,meas.FX);
                case {FitMode.Fy0, FitMode.Fy}
                    testdata = cat(1,meas.FYW);
                case FitMode.Mz0
                    error('Not yet implemented')
                case FitMode.Mx
                    error('Not yet implemented')
                case FitMode.My
                    error('Not yet implemented')
                case FitMode.Fz
                    error('Not yet implemented')
                case FitMode.Mz
                    error('Not yet implemented')
            end
            
            costFun = @(x) fitter.costFun(x,params,mfinputs,testdata,fitmode);
            [x0,lb,ub] = convert2fittable(params,fitmode);
            nonlcon = @(x) fitter.constraints(x,params,fitmode,mfinputs);
            options = fitter.Options;
            x = fmincon(costFun,x0,[],[],[],[],lb,ub,nonlcon,options);
        end
        function run(fitter)
            import mftyre.v62.FitMode
            
            fitmodes = fitter.FitModes;
            fitter.ParametersFitted = fitter.Parameters;
            for i = 1:numel(fitmodes)
                fitmode = fitmodes(i);
                try
                    tic; x = fitter.solve(fitmode); t = toc;
                    fprintf('Time elapsed %.1fs.\n', t)
                    p = appendFitted(fitter.ParametersFitted, x, fitmode);
                    fitter.ParametersFitted = p;
                catch ME
                    % TODO: exception
                end
            end
        end
        function fitter = Fitter(measurements, parameters)
            arguments
                measurements tydex.Measurement = tydex.Measurement.empty
                parameters mftyre.v62.Parameters = mftyre.v62.Parameters.empty
            end
            fitter.Measurements = measurements;
            fitter.Parameters = parameters;
        end
    end
    methods (Access = private)
        function qualifyMeasurements(fitter)
            % QUALITFYMEASUREMENTS Finds which measurements can be used for
            % which fit-mode. For example, data which only includes
            % slip-free slip angle sweeps can only be used to fit Fy0.
            %
            measurements = fitter.Measurements;
            
            if isempty(measurements)
                return
            end
            
            numMeas = numel(measurements);
            
            modes = enumeration(mftyre.v62.FitMode.Fy0);
            keys = cell(numel(modes),1);
            for i = 1:numel(modes)
                keys{i} = char(modes(i));
            end
            vals = cell(size(keys));
            
            % Fx0
            idx = zeros(numMeas,1);
            for i = 1:numMeas
                const = measurements(i).Constant;
                I = strcmp({const.Name},'SLIPANGL');
                if any(I) && const(I).Value == 0; idx(i) = 1; end
            end
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Fx0)),1);
            vals{key} = find(idx);
            
            % Fy0 + Mz0
            idx = zeros(numMeas,1);
            for i = 1:numMeas
                const = measurements(i).Constant;
                I = strcmp({const.Name},'LONGSLIP');
                if any(I) && const(I).Value == 0; idx(i) = 1; end
            end
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Fy0)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Mz0)),1);
            vals{key} = find(idx);
            
            % Mz + Fx + Fy + Fz + Mx + My (Combined Slip)
            idx = zeros(numMeas,1);
            for i = 1:numMeas
                const = measurements(i).Constant;
                I1 = strcmp({const.Name},'LONGSLIP');
                I2 = strcmp({const.Name},'SLIPANGL');
                if (any(I1) && const(I1).Value == 0) || (any(I2) && const(I2).Value == 0)
                    idx(i) = 0;
                else
                    idx(i) = 1;
                end
            end
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Mz)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Fx)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Fy)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Mx)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.My)),1);
            vals{key} = find(idx);
            key = find(strcmp(keys,char(mftyre.v62.FitMode.Fz)),1);
            vals{key} = find(idx);
            
            fitModeFlagsMap = containers.Map(keys,vals);
            fitter.FitModeFlags = fitModeFlagsMap;
        end
    end
    methods (Static, Access = private)
        function cost = costFun(x,params,mfinputs,testdata,fitmode)
            %COSTFUN Summed squares cost function for fmincon solver.
            arguments
                x        double
                params   mftyre.v62.Parameters
                mfinputs double
                testdata double
                fitmode  mftyre.v62.FitMode
            end
            import('mftyre.v62.FitMode')
            import('mftyre.v62.equations.Fx0')
            import('mftyre.v62.equations.Fy0')
            import('mftyre.v62.equations.Fx')
            import('mftyre.v62.equations.Fy')
            
            params = appendFitted(params,x,fitmode);
            params = struct(params);
            
            switch fitmode
                case FitMode.Fx0
                    longslip = mfinputs(:,2);
                    pressure = mfinputs(:,7);
                    inclangl = mfinputs(:,4);
                    Fz       = mfinputs(:,1);
                    modelout = Fx0(params,longslip,inclangl,pressure,Fz);
                case FitMode.Fy0
                    slipangl = mfinputs(:,3);
                    pressure = mfinputs(:,7);
                    inclangl = mfinputs(:,4);
                    Fz       = mfinputs(:,1);
                    modelout = Fy0(params,slipangl,inclangl,pressure,Fz);
                case FitMode.Fx
                    slipangl = mfinputs(:,3);
                    longslip = mfinputs(:,2);
                    pressure = mfinputs(:,7);
                    inclangl = mfinputs(:,4);
                    Fz       = mfinputs(:,1);
                    modelout = Fx(params,slipangl,longslip,inclangl,pressure,Fz);
                case FitMode.Fy
                    slipangl = mfinputs(:,3);
                    longslip = mfinputs(:,2);
                    pressure = mfinputs(:,7);
                    inclangl = mfinputs(:,4);
                    Fz       = mfinputs(:,1);
                    modelout = Fy(params,slipangl,longslip,inclangl,pressure,Fz);
                case FitMode.Fz
                    warning('Not implemented yet')
                case FitMode.Mx
                    warning('Not implemented yet')
                case FitMode.My
                    warning('Not implemented yet')
                case {FitMode.Mz0, FitMode.Mz}
                    warning('Not implemented yet')
            end
            
            cost = sum((testdata-modelout).^2);
            cost = double(cost);
        end
        function [c,ceq] = constraints(x,params,fitmode,mfinputs)
            %CONSTRAINTS Constraints for fmincon solver.
            arguments
                x double
                params mftyre.v62.Parameters
                fitmode mftyre.v62.FitMode
                mfinputs double
            end
            c = []; ceq = [];
            import('mftyre.v62.FitMode')
            params = appendFitted(params,x,fitmode);
            params = struct(params);
            longslip = mfinputs(:,2);
            slipangl = mfinputs(:,3);
            inclangl = mfinputs(:,4);
            pressure = mfinputs(:,7);
            Fz = mfinputs(:,1);
            switch fitmode
                case FitMode.Fx0
                    [~,~,Cx,Dx,Ex] = mftyre.v62.equations.Fx0(params,...
                        longslip,inclangl,pressure,Fz);
                    c = [-Cx+eps;-Dx+eps;Ex-1];
                case FitMode.Fy0
                    [~,~,~,Cy,Ey] = mftyre.v62.equations.Fy0(params,...
                        slipangl,inclangl,pressure,Fz);
                    c = [-Cy+eps;Ey-1];
                case FitMode.Fx
                    [~,~,Gxa,Bxa,Exa] = mftyre.v62.equations.Fx(params,...
                        slipangl,longslip,inclangl,pressure,Fz);
                    c = [-Gxa+eps;-Bxa+eps;Exa-1];
                case FitMode.Fy
                    [~,~,Gyk,Byk,Eyk] = mftyre.v62.equations.Fy(params,...
                        slipangl,longslip,inclangl,pressure,Fz);
                    c = [-Gyk+eps;-Byk+eps;Eyk-1];
                case FitMode.Mz0
                    warning('Constraints for Mz0 not yet implemented')
                case FitMode.Mz
                    warning('Constraints for Mz not yet implemented')
                case FitMode.Mx
                    warning('Constraints for Mx not yet implemented')
                case FitMode.My
                    warning('Constraints for My not yet implemented')
                case FitMode.Fz
                    warning('Constraints for Fz not yet implemented')
            end
        end
        function [mfinputs] = preprocess(measurements)
            %PREPROCESS Returns one big matrix of test data for fitting.
            arguments
                measurements tydex.Measurement
            end
            param = {
                'FZW'
                'LONGSLIP'
                'SLIPANGL'
                'INCLANGL'
                ''
                'LONGVEL'
                'INFLPRES'
                };
            mfinputs = zeros(length(measurements),7);
            endIdx = 0;
            for num = 1:numel(measurements)
                startIdx = endIdx + 1;
                endIdx = endIdx + length(measurements(num));
                for i = 1:numel(param)
                    if isempty(param{i})
                        input = zeros(length(measurements(num)),1);
                    else
                        input = measurements(num).(param{i});
                        if isscalar(input)
                            input = input*ones(length(measurements(num)),1);
                        end
                    end
                    mfinputs(startIdx:endIdx,i) = input;
                end
            end
        end
    end
end
// Simulator Stages level helper: this mod's own part. tools/make_helper_source.py stitches it together with
// sections copied from Junon Colosseum's helper to make main.cpp. NOT YET RUN IN THE GAME (2026-11-16).
//
// What it does: UE4SS 3.0.1's Lua cannot call LevelStreamingDynamic.LoadLevelInstance (the function's bool
// out-parameter breaks the Lua argument stack), so this helper makes that one call. The Lua side writes requests to
// stages-request.txt in the mod's folder; the helper takes them on the game thread, at a Blueprint tick, one per
// frame, while the package loader is idle, and writes the outcome to stages-ack.txt. It also writes
// stages-helper.txt twice a second so the Lua side can tell it is alive and able to work.
//
// It reads no game memory beyond what the copied sections check byte for byte, writes none, and changes no save.
namespace
{
    std::atomic<bool> faulted{false};
    void Say(const std::string& line) noexcept
    {
        std::string message="[SimulatorStages] "+line+"\n";
        printf_s("%s",message.c_str());
        try {
            const std::wstring wide(message.begin(),message.end());
            RC::Output::send(std::wstring_view(wide));
        } catch(...) {}
    }
    // A check on the game's code failed: say so once and do no engine work. Junon Colosseum shows a window here;
    // this mod only loses its streamed stages, so a log line is enough.
    void Fault(const char* code,const std::string& logLine,const std::wstring&) noexcept
    {
        if(!faulted.exchange(true)) Say(std::string(code)+": "+logLine+" Streamed stages are off.");
    }
// ==== COPIED SECTIONS GO HERE ====
    // ---- this mod's own request loop ----

    // LevelStreamingDynamic.LoadLevelInstance(WorldContextObject, LevelName, Location, Rotation, bOutSuccess,
    // OptionalLevelNameOverride), through reflection: every offset and size comes from the function's own
    // properties, as in Junon Colosseum's LoadOwnedLevel, which leaves Location and Rotation at zero. Here they are
    // set: a stage's levels are placed so that its fight centre lands on the simulator's centre.
    RC::Unreal::UObject* LoadLevel(RC::Unreal::UObject* context,const std::wstring& packagePath,const std::wstring& instanceName,
                                   float x,float y,float z,float yaw,std::string& why)
    {
        using namespace RC::Unreal;
        auto* api=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,STR("/Script/Engine.Default__LevelStreamingDynamic"));
        auto* fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Engine.LevelStreamingDynamic:LoadLevelInstance"));
        if(!api || !fn){ why="function_or_default_missing"; return nullptr; }
        if(fn->GetNumParms()!=7 || fn->GetPropertiesSize()<8 || fn->GetPropertiesSize()>256){ why="unexpected_parameter_block"; return nullptr; }
        struct Parameters {
            std::vector<uint8_t> bytes;
            std::vector<FProperty*> fields;
            ~Parameters(){for(auto it=fields.rbegin();it!=fields.rend();++it)(*it)->DestroyValue_InContainer(bytes.data());}
        } params{std::vector<uint8_t>(fn->GetPropertiesSize()),{}};
        FProperty *world=nullptr,*path=nullptr,*location=nullptr,*rotation=nullptr,*success=nullptr,*name=nullptr,*result=nullptr;
        for(auto* field:fn->ForEachProperty()){
            if(!field->HasAnyPropertyFlags(CPF_Parm))continue;
            if(field->GetArrayDim()!=1 || field->GetOffset_Internal()<0 || field->GetElementSize()<1 ||
               field->GetOffset_Internal()+field->GetElementSize()>fn->GetPropertiesSize()){ why="field_outside_parameter_block"; return nullptr; }
            field->InitializeValue_InContainer(params.bytes.data());params.fields.push_back(field);
            const auto n=field->GetName();
            if(n==STR("WorldContextObject"))world=field;
            else if(n==STR("LevelName"))path=field;
            else if(n==STR("Location"))location=field;
            else if(n==STR("Rotation"))rotation=field;
            else if(n==STR("bOutSuccess"))success=field;
            else if(n==STR("OptionalLevelNameOverride"))name=field;
            else if(n==STR("ReturnValue"))result=field;
            else { why="unknown_parameter"; return nullptr; }
        }
        if(params.fields.size()!=7 || !world || !path || !name || !location || !rotation || !success || !result ||
           !world->IsA<FObjectProperty>() || !path->IsA<FStrProperty>() || !name->IsA<FStrProperty>() ||
           !location->IsA<FStructProperty>() || !rotation->IsA<FStructProperty>() ||
           !success->IsA<FBoolProperty>() || !result->IsA<FObjectProperty>() ||
           location->GetElementSize()!=12 || rotation->GetElementSize()!=12 ||
           world->GetElementSize()!=sizeof(UObject*) || result->GetElementSize()!=sizeof(UObject*) ||
           path->GetElementSize()!=sizeof(FString) || name->GetElementSize()!=sizeof(FString)){ why="parameter_type_or_size"; return nullptr; }
        FString package(packagePath.c_str());
        FString leaf(instanceName.c_str());
        world->CopySingleValue(world->ContainerPtrToValuePtr<void>(params.bytes.data()),&context);
        path->CopySingleValue(path->ContainerPtrToValuePtr<void>(params.bytes.data()),&package);
        name->CopySingleValue(name->ContainerPtrToValuePtr<void>(params.bytes.data()),&leaf);
        // FVector is X, Y, Z and FRotator is Pitch, Yaw, Roll: three floats each (sizes checked above).
        const float where[3]={x,y,z};
        const float turn[3]={0.0f,yaw,0.0f};
        std::memcpy(location->ContainerPtrToValuePtr<void>(params.bytes.data()),where,sizeof where);
        std::memcpy(rotation->ContainerPtrToValuePtr<void>(params.bytes.data()),turn,sizeof turn);
        api->ProcessEvent(fn,params.bytes.data());
        const bool ok=static_cast<FBoolProperty*>(success)->GetPropertyValueInContainer(params.bytes.data());
        UObject* stream=*result->ContainerPtrToValuePtr<UObject*>(params.bytes.data());
        if(!ok) why="load_refused";
        else if(!stream) why="no_stream_returned";
        return ok ? stream : nullptr;
    }
    // LevelStreaming.SetIsRequestingUnloadAndRemoval(true) on a stream this helper loaded: one bool parameter,
    // its type taken from the function's own properties.
    bool UnloadStream(RC::Unreal::UObject* stream,std::string& why)
    {
        using namespace RC::Unreal;
        auto* fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Engine.LevelStreaming:SetIsRequestingUnloadAndRemoval"));
        if(!fn){ why="function_missing"; return false; }
        if(fn->GetNumParms()!=1 || fn->GetPropertiesSize()<1 || fn->GetPropertiesSize()>16){ why="unexpected_parameter_block"; return false; }
        std::vector<uint8_t> bytes(fn->GetPropertiesSize());
        FProperty* flag=nullptr;
        for(auto* field:fn->ForEachProperty()) if(field->HasAnyPropertyFlags(CPF_Parm)) flag=field;
        if(!flag || !flag->IsA<FBoolProperty>()){ why="parameter_type"; return false; }
        static_cast<FBoolProperty*>(flag)->SetPropertyValueInContainer(bytes.data(),true);
        stream->ProcessEvent(fn,bytes.data());
        return true;
    }

    // Requests, game thread only. A line of stages-request.txt is: load <tab> name <tab> package <tab> x <tab> y
    // <tab> z <tab> yaw, or: unload <tab> name. The file is renamed before it is read, so a request written meanwhile is not lost.
    struct Request { bool unload=false; std::wstring package, name; float x=0,y=0,z=0,yaw=0; ULONGLONG at=0; };
    std::vector<Request> queue;
    // The streams this helper loaded, by instance name, so it can unload them. Only the address is kept (live
    // 2026-11-17: a weak pointer assigned here never resolved again); before it is used, StillThere() confirms it
    // is still one of the game's LevelStreamingDynamic objects.
    std::unordered_map<std::wstring,RC::Unreal::UObject*> streams;
    bool StillThere(RC::Unreal::UObject* wanted)
    {
        std::vector<RC::Unreal::UObject*> all;
        RC::Unreal::UObjectGlobals::FindAllOf(STR("LevelStreamingDynamic"),all);
        return std::find(all.begin(),all.end(),wanted)!=all.end();
    }
    constexpr ULONGLONG MaxDefer=8000;   // ms a request waits for the loader to go idle before it is served anyway
    constexpr size_t MaxQueue=64;

    void Ack(const std::wstring& name,const std::string& result)
    {
        std::ofstream out(Shared("stages-ack.txt"),std::ios::app);
        out<<std::string(name.begin(),name.end())<<"\t"<<result<<"\n";
    }
    void Intake(ULONGLONG now)
    {
        static ULONGLONG next=0;
        if(now<next) return;
        next=now+200;
        std::error_code ec;
        const std::filesystem::path request=Shared("stages-request.txt"), taken=Shared("stages-request.taken");
        if(!std::filesystem::exists(request,ec)) return;
        std::filesystem::remove(taken,ec);
        std::filesystem::rename(request,taken,ec);
        if(ec) return;
        std::ifstream in(taken);
        std::string line;
        while(std::getline(in,line)){
            while(!line.empty() && (line.back()=='\r' || line.back()==' ')) line.pop_back();
            std::vector<std::string> part;
            std::stringstream fields(line);
            std::string field;
            while(std::getline(fields,field,'\t')) part.push_back(field);
            if(part.size()==2 && part[0]=="unload"){
                Request u;
                u.unload=true;
                u.name.assign(part[1].begin(),part[1].end());
                u.at=now;
                if(queue.size()<MaxQueue) queue.push_back(u);
                continue;
            }
            if(part.size()!=7 || part[0]!="load") continue;
            Request r;
            r.name.assign(part[1].begin(),part[1].end());
            r.package.assign(part[2].begin(),part[2].end());
            try { r.x=std::stof(part[3]); r.y=std::stof(part[4]); r.z=std::stof(part[5]); r.yaw=std::stof(part[6]); }
            catch(...) { Ack(r.name,"refused\tbad_number"); continue; }
            // Only this game's own level packages, and a plain instance name.
            const bool plainName=!r.name.empty() && r.name.size()<=96 &&
                std::all_of(r.name.begin(),r.name.end(),[](wchar_t c){ return (c>=L'A'&&c<=L'Z')||(c>=L'a'&&c<=L'z')||(c>=L'0'&&c<=L'9')||c==L'_'; });
            if(r.package.rfind(L"/Game/Level/",0)!=0 || r.package.size()>300 || !plainName){ Ack(r.name,"refused\tbad_request"); continue; }
            if(queue.size()>=MaxQueue){ Ack(r.name,"refused\tqueue_full"); continue; }
            r.at=now;
            queue.push_back(r);
        }
        in.close();
        std::filesystem::remove(taken,ec);
    }
    // Twice a second: proof for the Lua side that the helper is running on the game thread and its checks passed.
    void Beat(ULONGLONG now,bool loading)
    {
        static ULONGLONG next=0;
        if(now<next) return;
        next=now+500;
        const std::string path=Shared("stages-helper.txt");
        {
            std::ofstream out(path+".tmp",std::ios::trunc);
            out<<"tick\t"<<now<<"\nready\t"<<(Loader::Verify()&&!faulted.load()?1:0)<<"\nloading\t"<<(loading?1:0)<<"\nqueued\t"<<queue.size()<<"\n";
        }
        std::error_code ec;
        std::filesystem::rename(path+".tmp",path,ec);
    }
    // Every game-thread ProcessEvent of a Blueprint tick or camera update: take new requests, and serve at most one.
    void AtSafePoint(RC::Unreal::UObject* object,RC::Unreal::UFunction* function,const char* kind)
    {
        thread_local bool busy=false;   // the load re-enters ProcessEvent
        if(busy) return;
        busy=true;
        try {
            const ULONGLONG now=GetTickCount64();
            const bool verified=Loader::Verify() && !faulted.load();
            const bool loading=verified && Loader::Busy();
            Beat(now,loading);
            if(verified){
                Intake(now);
                // The world context has to be an actor in the world: an actor's own tick.
                const bool actorTick=std::strcmp(kind,"receive_tick")==0 && object && object->IsA<RC::Unreal::AActor>();
                if(!queue.empty() && actorTick && SafePoint::Open(object,function) &&
                   (!loading || (!queue.front().unload && now-queue.front().at>=MaxDefer))){   // an unload searches the game's objects: only while idle
                    const Request r=queue.front();
                    queue.erase(queue.begin());
                    std::string why;
                    bool ok=false;
                    try {
                        if(r.unload){
                            const auto found=streams.find(r.name);
                            RC::Unreal::UObject* stream=found==streams.end()?nullptr:found->second;
                            if(!stream) why="not_loaded_by_helper";
                            else if(!StillThere(stream)) why="already_gone";
                            else ok=UnloadStream(stream,why);
                            if(found!=streams.end()) streams.erase(found);
                        }else{
                            RC::Unreal::UObject* stream=LoadLevel(object,r.package,r.name,r.x,r.y,r.z,r.yaw,why);
                            ok=stream!=nullptr;
                            if(ok) streams[r.name]=stream;
                        }
                    }
                    catch(const std::exception& error) { why=std::string("cpp_exception ")+error.what(); }
                    catch(...) { why="cpp_exception"; }
                    Ack(r.name,ok?std::string(r.unload?"unloaded":"loaded")+"\t"+std::to_string(now-r.at)+"ms":"refused\t"+why);
                    SafePoint::Close(object,function);
                }
            }
        } catch(...) {}
        busy=false;
    }

    class SimulatorStagesHelper : public RC::CppUserModBase
    {
    public:
        SimulatorStagesHelper()
        {
            ModName = STR("Simulator Stages level helper");
            ModVersion = STR("0.1.0");
            ModDescription = STR("Loads a stage's levels at the combat simulator's position for the Simulator Stages mod");
            ModAuthors = STR("CaitGPT");
        }
        void on_unreal_init() override
        {
            std::error_code ec;
            std::filesystem::remove(Shared("stages-request.txt"),ec);   // nothing left over from an earlier run
            std::filesystem::remove(Shared("stages-ack.txt"),ec);
            std::filesystem::remove(Shared("stages-helper.txt"),ec);
            SafePoint::Init();
            RC::Unreal::Hook::RegisterProcessEventPreCallback([](auto* object,auto* function,void*) {
                const char* kind=SafePoint::Kind(function);
                if(!kind) return;                 // a name compare on every ProcessEvent, nothing more
                if(!OnGameThread()) return;       // engine work only where the loader keeps its state
                AtSafePoint(object,function,kind);
            });
            Say("level helper ready");
        }
    };
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new SimulatorStagesHelper(); }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }

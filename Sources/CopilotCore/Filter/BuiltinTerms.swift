import Foundation

/// Встроенный список английских IT-терминов и общепринятых выражений собеседований (COPILOT-05 R-05, Q9).
/// Слова в нижнем регистре; составные термины — по словам («pull request» = «pull» + «request»).
/// Дополняется словами латиницей из резюме, вакансии и базы вопросов (`TermDictionary.add`).
enum BuiltinTerms {
    static let words: Set<String> = Set(list.split(whereSeparator: \.isWhitespace).map(String.init))

    /// Служебные слова между терминами: «CI and CD», «unit and integration tests».
    static let glue: Set<String> = ["and", "or", "the", "a", "an", "of", "to", "in", "on", "for", "with", "vs", "via", "&"]

    private static let list = """
    api apis rest restful graphql grpc soap http https json xml yaml csv protobuf websocket websockets socket sockets
    sql nosql postgresql postgres mysql sqlite mongodb mongo redis memcached kafka rabbitmq elasticsearch clickhouse
    cassandra dynamodb firebase firestore supabase realm coredata keychain userdefaults
    docker kubernetes k8s helm terraform ansible jenkins aws gcp azure lambda s3 ec2 ecs eks cloudflare vercel heroku nginx
    ci cd ci/cd cicd devops sre mlops pipeline pipelines build builds deploy deployment deployments release releases rollback
    rollout canary blue green hotfix staging production prod dev
    git github gitlab bitbucket jira confluence notion slack figma miro trello
    agile scrum kanban sprint sprints standup daily retro retrospective backlog grooming planning story stories epic epics
    estimate estimation velocity burndown
    code review reviews pull request requests pr prs merge rebase commit commits branch branches cherry-pick fork
    feature features flag flags toggle bug bugs fix fixes issue issues ticket tickets task tasks
    test tests testing unit integration e2e end-to-end ui snapshot regression tdd bdd qa mock mocks stub stubs coverage
    swift swiftui uikit objective-c objc ios ipados macos watchos tvos visionos xcode instruments testflight appstore
    android kotlin java jetpack compose gradle flutter dart react native reactnative expo
    javascript typescript js ts node nodejs deno bun npm yarn pnpm webpack vite babel eslint prettier
    angular vue svelte nextjs next.js nuxt redux mobx rxjs html css sass tailwind
    python django flask fastapi pandas numpy pytorch tensorflow jupyter
    go golang rust c c++ cpp c# .net dotnet php laravel symfony ruby rails scala elixir haskell
    spring boot hibernate maven
    backend frontend fullstack full-stack mobile web desktop embedded cloud serverless saas paas iaas
    microservice microservices monolith architecture architect design system systems pattern patterns
    mvc mvp mvvm viper tca redux clean solid dry kiss yagni oop fp functional reactive
    dependency injection di singleton factory builder adapter observer delegate delegation coordinator router
    async await concurrency concurrent parallel parallelism thread threads threading multithreading queue queues gcd
    combine rxswift coroutine coroutines actor actors mutex lock locks semaphore deadlock race condition
    memory leak leaks arc retain cycle weak strong unowned garbage collector gc heap stack
    cache caching cdn load balancer balancing scaling scalability horizontal vertical sharding replication
    latency throughput performance optimization profiling benchmark benchmarks bottleneck
    crash crashes crashlytics sentry analytics metrics monitoring logging logs observability grafana prometheus datadog
    kpi kpis okr okrs sla slo roadmap mvp poc prototype
    ml ai llm llms gpt chatgpt openai claude gemini copilot nlp cv data dataset etl big spark hadoop airflow dashboard
    oauth oauth2 jwt sso saml ssl tls https encryption security owasp xss csrf auth authentication authorization
    push notification notifications background foreground lifecycle
    view views controller controllers viewmodel viewcontroller model models storyboard xib autolayout constraints
    protocol protocols extension extensions generics generic closure closures optional optionals enum enums struct structs
    class classes value reference type types copy-on-write codable
    algorithm algorithms complexity big-o o(n) array arrays list lists linked hash hashmap map set tree trees graph graphs
    binary search sort sorting recursion recursive dynamic programming greedy bfs dfs leetcode
    sdk sdks framework frameworks library libraries ide cocoapods spm carthage linter lint refactoring refactor legacy
    tech debt technical migration versioning semver open-source opensource
    product manager pm po owner team lead teamlead techlead senior middle junior intern cto ceo hr recruiter
    stakeholder stakeholders deadline deadlines feedback one-on-one 1:1 onboarding offboarding offer salary bonus
    remote hybrid office startup enterprise b2b b2c fintech edtech healthtech ecommerce e-commerce marketplace
    interview interviews behavioral star case cases edge
    ok okay yes no yeah yep sure exactly right cool nice great good perfect thanks thank sorry please hello hi bye well so
    """
}

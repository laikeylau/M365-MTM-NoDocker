import React from 'react'
import dynamic from 'next/dynamic'

import '../i18n'

const App = dynamic(() => import('./_app-inner'), { ssr: false })

export default App
